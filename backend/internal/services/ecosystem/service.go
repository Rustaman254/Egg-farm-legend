// Package ecosystem implements the Ecosystem Task Service: tasks completed by real on-chain
// activity on Arbitrum itself, not just our own game contracts -- holding ARB, being an active
// wallet, receiving a real ARB token transfer. Two verification strategies:
//
//   - Balance/tx-count checks (RunBalanceChecks): periodic direct RPC reads (eth_getBalance,
//     eth_getTransactionCount, balanceOf) against every known player wallet. No indexing needed
//     since these are simple current-state reads, not events to replay.
//   - Event checks (RunTokenReceivedChecks): a generic ERC-20 Transfer-event indexer, same
//     cursor-based polling pattern as internal/services/marketplace and gamestate, but driven by
//     a DB-configured contract address instead of one of our own deployed contracts. This is
//     what proves task verification generalizes to arbitrary Arbitrum ecosystem contracts, not
//     just ones we deployed.
//
// Both feed into the same task_progress machinery as our own game-event tasks (see
// internal/services/task) -- a task is a task, regardless of what convinced the backend it's
// complete.
package ecosystem

import (
	"context"
	"encoding/hex"
	"fmt"
	"log/slog"
	"math/big"
	"time"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ChainReader is satisfied by internal/chain.Client.
type ChainReader interface {
	NativeBalance(ctx context.Context, wallet string) (*big.Int, error)
	TxCount(ctx context.Context, wallet string) (uint64, error)
	TokenBalance(ctx context.Context, tokenAddress, wallet string) (*big.Int, error)
	CallViewFunction(ctx context.Context, contractAddress string, selector [4]byte, wallet string) ([]byte, error)
	FilterLogs(ctx context.Context, addresses []common.Address, fromBlock, toBlock uint64) ([]types.Log, error)
	LatestBlock(ctx context.Context) (uint64, error)
	BlockTime(ctx context.Context, blockNumber uint64) (time.Time, error)
	ERC20ABI() abi.ABI
}

// ProgressRecorder is satisfied by internal/services/task.Service.
type ProgressRecorder interface {
	RecordProgressAt(ctx context.Context, wallet, taskID string, delta int, at time.Time) error
}

type Service struct {
	db    *pgxpool.Pool
	chain ChainReader
	tasks ProgressRecorder
}

func NewService(db *pgxpool.Pool, chain ChainReader, tasks ProgressRecorder) *Service {
	return &Service{db: db, chain: chain, tasks: tasks}
}

type ecosystemTask struct {
	id               string
	checkType        string
	contractAddress  *string
	thresholdWei     *string
	thresholdCount   *int
	deployBlock      int64
	functionSelector *string
	outputType       *string
	eventTopic0      *string
	walletTopicIndex *int
}

// ConfigureContractAddress sets (or clears) a task's target contract address -- e.g. wiring the
// real ARB token address into arb_token_holder/arb_token_received at startup, from an env var,
// since the token doesn't exist at the same address (or at all) on every network this project
// might be pointed at.
func (s *Service) ConfigureContractAddress(ctx context.Context, taskID, address string) error {
	_, err := s.db.Exec(ctx, `UPDATE tasks SET contract_address = $2 WHERE id = $1`, taskID, address)
	if err != nil {
		return fmt.Errorf("configuring contract address for task %s: %w", taskID, err)
	}
	return nil
}

func (s *Service) loadTasks(ctx context.Context, checkTypes ...string) ([]ecosystemTask, error) {
	rows, err := s.db.Query(ctx, `
		SELECT id, check_type, contract_address, threshold_wei, threshold_count, deploy_block,
		       function_selector, output_type, event_topic0, wallet_topic_index
		FROM tasks
		WHERE is_active AND check_type = ANY($1) AND (expires_at IS NULL OR expires_at > now())`, checkTypes)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []ecosystemTask
	for rows.Next() {
		var t ecosystemTask
		if err := rows.Scan(&t.id, &t.checkType, &t.contractAddress, &t.thresholdWei, &t.thresholdCount, &t.deployBlock,
			&t.functionSelector, &t.outputType, &t.eventTopic0, &t.walletTopicIndex); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

func (s *Service) playerWallets(ctx context.Context) ([]string, error) {
	rows, err := s.db.Query(ctx, `SELECT wallet_address FROM players`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []string
	for rows.Next() {
		var w string
		if err := rows.Scan(&w); err != nil {
			return nil, err
		}
		out = append(out, w)
	}
	return out, rows.Err()
}

// RunBalanceChecks periodically sweeps every native_balance/token_balance/tx_count task against
// every known player wallet. Ticks on `interval` until ctx is cancelled.
func (s *Service) RunBalanceChecks(ctx context.Context, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	s.balanceTick(ctx)
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.balanceTick(ctx)
		}
	}
}

func (s *Service) balanceTick(ctx context.Context) {
	tasks, err := s.loadTasks(ctx, "native_balance", "token_balance", "tx_count", "view_function")
	if err != nil {
		slog.Error("ecosystem service: loading balance tasks failed", "error", err)
		return
	}
	if len(tasks) == 0 {
		return
	}

	wallets, err := s.playerWallets(ctx)
	if err != nil {
		slog.Error("ecosystem service: loading player wallets failed", "error", err)
		return
	}

	now := time.Now()
	for _, task := range tasks {
		for _, wallet := range wallets {
			met, err := s.checkBalanceTask(ctx, task, wallet)
			if err != nil {
				slog.Error("ecosystem service: check failed", "taskId", task.id, "wallet", wallet, "error", err)
				continue
			}
			if met {
				if err := s.tasks.RecordProgressAt(ctx, wallet, task.id, 1, now); err != nil {
					slog.Error("ecosystem service: recording progress failed", "taskId", task.id, "wallet", wallet, "error", err)
				}
			}
		}
	}
}

func (s *Service) checkBalanceTask(ctx context.Context, task ecosystemTask, wallet string) (bool, error) {
	switch task.checkType {
	case "native_balance":
		if task.thresholdWei == nil {
			return false, nil
		}
		threshold, ok := new(big.Int).SetString(*task.thresholdWei, 10)
		if !ok {
			return false, fmt.Errorf("invalid threshold_wei %q", *task.thresholdWei)
		}
		balance, err := s.chain.NativeBalance(ctx, wallet)
		if err != nil {
			return false, err
		}
		return balance.Cmp(threshold) >= 0, nil

	case "token_balance":
		if task.thresholdWei == nil || task.contractAddress == nil {
			return false, nil // not configured for this network yet
		}
		threshold, ok := new(big.Int).SetString(*task.thresholdWei, 10)
		if !ok {
			return false, fmt.Errorf("invalid threshold_wei %q", *task.thresholdWei)
		}
		balance, err := s.chain.TokenBalance(ctx, *task.contractAddress, wallet)
		if err != nil {
			return false, err
		}
		return balance.Cmp(threshold) >= 0, nil

	case "tx_count":
		if task.thresholdCount == nil {
			return false, nil
		}
		count, err := s.chain.TxCount(ctx, wallet)
		if err != nil {
			return false, err
		}
		return count >= uint64(*task.thresholdCount), nil

	case "view_function":
		if task.functionSelector == nil || task.contractAddress == nil || task.outputType == nil {
			return false, nil // not fully configured
		}
		selectorBytes, err := hex.DecodeString(*task.functionSelector)
		if err != nil || len(selectorBytes) != 4 {
			return false, fmt.Errorf("invalid function_selector %q", *task.functionSelector)
		}
		var selector [4]byte
		copy(selector[:], selectorBytes)

		result, err := s.chain.CallViewFunction(ctx, *task.contractAddress, selector, wallet)
		if err != nil {
			return false, err
		}
		if len(result) == 0 {
			return false, nil
		}
		if *task.outputType == "bool" {
			return result[len(result)-1] != 0, nil
		}
		if task.thresholdWei == nil {
			return false, nil
		}
		threshold, ok := new(big.Int).SetString(*task.thresholdWei, 10)
		if !ok {
			return false, fmt.Errorf("invalid threshold_wei %q", *task.thresholdWei)
		}
		return new(big.Int).SetBytes(result).Cmp(threshold) >= 0, nil

	default:
		return false, nil
	}
}

// RunTokenReceivedChecks indexes Transfer events for every configured token_received task,
// crediting progress to whichever wallet received the transfer. Ticks on `interval`.
func (s *Service) RunTokenReceivedChecks(ctx context.Context, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	s.tokenReceivedTick(ctx)
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.tokenReceivedTick(ctx)
		}
	}
}

func (s *Service) tokenReceivedTick(ctx context.Context) {
	tasks, err := s.loadTasks(ctx, "token_received")
	if err != nil {
		slog.Error("ecosystem service: loading token_received tasks failed", "error", err)
		return
	}

	latest, err := s.chain.LatestBlock(ctx)
	if err != nil {
		slog.Error("ecosystem service: fetching latest block failed", "error", err)
		return
	}

	erc20ABI := s.chain.ERC20ABI()
	transferEvent := erc20ABI.Events["Transfer"]
	blockTimeCache := make(map[uint64]time.Time)

	for _, task := range tasks {
		if task.contractAddress == nil {
			continue // not configured for this network yet
		}
		s.indexTokenReceived(ctx, task, *task.contractAddress, latest, erc20ABI, transferEvent, blockTimeCache)
	}
}

func (s *Service) indexTokenReceived(
	ctx context.Context,
	task ecosystemTask,
	contractAddress string,
	latest uint64,
	erc20ABI abi.ABI,
	transferEvent abi.Event,
	blockTimeCache map[uint64]time.Time,
) {
	cursorKey := "ecosystem:" + task.id
	from, err := s.loadCursor(ctx, cursorKey, uint64(task.deployBlock))
	if err != nil {
		slog.Error("ecosystem service: reading cursor failed", "taskId", task.id, "error", err)
		return
	}
	if from > latest {
		return
	}

	const batchSize = 2000
	addr := common.HexToAddress(contractAddress)

	for from <= latest {
		to := from + batchSize
		if to > latest {
			to = latest
		}

		logs, err := s.chain.FilterLogs(ctx, []common.Address{addr}, from, to)
		if err != nil {
			slog.Error("ecosystem service: filtering logs failed", "taskId", task.id, "from", from, "to", to, "error", err)
			return
		}

		for _, log := range logs {
			if len(log.Topics) == 0 || log.Topics[0] != transferEvent.ID {
				continue
			}
			if err := s.handleTransferSafely(ctx, task, erc20ABI, log, blockTimeCache); err != nil {
				slog.Error("ecosystem service: handling transfer log failed", "taskId", task.id, "txHash", log.TxHash.Hex(), "error", err)
			}
		}

		if err := s.saveCursor(ctx, cursorKey, to+1); err != nil {
			slog.Error("ecosystem service: saving cursor failed", "taskId", task.id, "error", err)
			return
		}
		from = to + 1
	}
}

// handleTransferSafely recovers from a decode panic on a single malformed log -- same defensive
// pattern as the marketplace/gamestate indexers, doubly important here since the contract
// address is operator-configured (ARB_TOKEN_ADDRESS), not a contract we deployed and control.
func (s *Service) handleTransferSafely(
	ctx context.Context,
	task ecosystemTask,
	erc20ABI abi.ABI,
	log types.Log,
	blockTimeCache map[uint64]time.Time,
) (err error) {
	defer func() {
		if r := recover(); r != nil {
			err = fmt.Errorf("panic handling transfer log: %v", r)
		}
	}()

	if len(log.Topics) < 3 {
		return nil // malformed/non-standard Transfer log; skip
	}
	to := common.HexToAddress(log.Topics[2].Hex())

	blockTime, ok := blockTimeCache[log.BlockNumber]
	if !ok {
		blockTime, err = s.chain.BlockTime(ctx, log.BlockNumber)
		if err != nil {
			return err
		}
		blockTimeCache[log.BlockNumber] = blockTime
	}

	if err := s.ensurePlayer(ctx, to.Hex()); err != nil {
		return err
	}
	return s.tasks.RecordProgressAt(ctx, to.Hex(), task.id, 1, blockTime)
}

// RunContractEventChecks indexes ALL logs from configured contract_event tasks' target contracts
// -- no event-signature filter, since a partner-created task targets a protocol whose ABI we
// don't know ahead of time. A wallet is credited the moment its address appears in any indexed
// topic of any log the contract emits: Solidity convention indexes the acting address on swaps,
// stakes, mints, and transfers alike, so this generalizes "prove you used this protocol" without
// needing to understand what the protocol's functions are called.
func (s *Service) RunContractEventChecks(ctx context.Context, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	s.contractEventTick(ctx)
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.contractEventTick(ctx)
		}
	}
}

func (s *Service) contractEventTick(ctx context.Context) {
	tasks, err := s.loadTasks(ctx, "contract_event")
	if err != nil {
		slog.Error("ecosystem service: loading contract_event tasks failed", "error", err)
		return
	}
	if len(tasks) == 0 {
		return
	}

	wallets, err := s.playerWallets(ctx)
	if err != nil {
		slog.Error("ecosystem service: loading player wallets failed", "error", err)
		return
	}
	walletByTopic := make(map[common.Hash]string, len(wallets))
	for _, w := range wallets {
		walletByTopic[common.BytesToHash(common.HexToAddress(w).Bytes())] = w
	}

	latest, err := s.chain.LatestBlock(ctx)
	if err != nil {
		slog.Error("ecosystem service: fetching latest block failed", "error", err)
		return
	}

	for _, task := range tasks {
		if task.contractAddress == nil {
			continue // not configured yet
		}
		s.indexContractEvent(ctx, task, *task.contractAddress, latest, walletByTopic, matchAnyIndexedTopic)
	}
}

// eventMatcher decides whether a log counts as progress and, if so, which wallet earns it --
// matchAnyIndexedTopic (contract_event: any event, any indexed address) and matchNamedEvent
// (named_event: one exact event, one exact indexed slot) are the two implementations.
type eventMatcher func(log types.Log, walletByTopic map[common.Hash]string) string

func matchAnyIndexedTopic(log types.Log, walletByTopic map[common.Hash]string) string {
	if len(log.Topics) < 2 {
		return "" // no indexed params to match against
	}
	for _, topic := range log.Topics[1:] {
		if w, ok := walletByTopic[topic]; ok {
			return w
		}
	}
	return ""
}

// matchNamedEvent builds a matcher for one specific event (topic0) with the wallet expected at
// one specific indexed slot -- precise "did you call *this* function" verification, as opposed
// to matchAnyIndexedTopic's "did you touch this contract at all".
func matchNamedEvent(topic0 common.Hash, walletTopicIndex int) eventMatcher {
	return func(log types.Log, walletByTopic map[common.Hash]string) string {
		if len(log.Topics) <= walletTopicIndex || log.Topics[0] != topic0 {
			return ""
		}
		if w, ok := walletByTopic[log.Topics[walletTopicIndex]]; ok {
			return w
		}
		return ""
	}
}

func (s *Service) indexContractEvent(
	ctx context.Context,
	task ecosystemTask,
	contractAddress string,
	latest uint64,
	walletByTopic map[common.Hash]string,
	match eventMatcher,
) {
	cursorKey := "ecosystem:" + task.id
	from, err := s.loadCursor(ctx, cursorKey, uint64(task.deployBlock))
	if err != nil {
		slog.Error("ecosystem service: reading cursor failed", "taskId", task.id, "error", err)
		return
	}
	if from > latest {
		return
	}

	const batchSize = 2000
	addr := common.HexToAddress(contractAddress)
	blockTimeCache := make(map[uint64]time.Time)

	for from <= latest {
		to := from + batchSize
		if to > latest {
			to = latest
		}

		logs, err := s.chain.FilterLogs(ctx, []common.Address{addr}, from, to)
		if err != nil {
			slog.Error("ecosystem service: filtering logs failed", "taskId", task.id, "from", from, "to", to, "error", err)
			return
		}

		for _, log := range logs {
			if err := s.handleContractLogSafely(ctx, task, log, walletByTopic, blockTimeCache, match); err != nil {
				slog.Error("ecosystem service: handling contract log failed", "taskId", task.id, "txHash", log.TxHash.Hex(), "error", err)
			}
		}

		if err := s.saveCursor(ctx, cursorKey, to+1); err != nil {
			slog.Error("ecosystem service: saving cursor failed", "taskId", task.id, "error", err)
			return
		}
		from = to + 1
	}
}

// handleContractLogSafely recovers from a decode panic on a single malformed log -- the contract
// address here is whatever a task creator typed in, not one we deployed and control.
func (s *Service) handleContractLogSafely(
	ctx context.Context,
	task ecosystemTask,
	log types.Log,
	walletByTopic map[common.Hash]string,
	blockTimeCache map[uint64]time.Time,
	match eventMatcher,
) (err error) {
	defer func() {
		if r := recover(); r != nil {
			err = fmt.Errorf("panic handling contract log: %v", r)
		}
	}()

	wallet := match(log, walletByTopic)
	if wallet == "" {
		return nil
	}

	blockTime, ok := blockTimeCache[log.BlockNumber]
	if !ok {
		blockTime, err = s.chain.BlockTime(ctx, log.BlockNumber)
		if err != nil {
			return err
		}
		blockTimeCache[log.BlockNumber] = blockTime
	}

	return s.tasks.RecordProgressAt(ctx, wallet, task.id, 1, blockTime)
}

// RunNamedEventChecks indexes logs for configured named_event tasks -- unlike
// RunContractEventChecks, each task matches exactly one event (by topic0) with the wallet
// expected at one specific indexed slot, so a creator can target "you called *this* function"
// precisely instead of "you touched this contract at all".
func (s *Service) RunNamedEventChecks(ctx context.Context, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	s.namedEventTick(ctx)
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.namedEventTick(ctx)
		}
	}
}

func (s *Service) namedEventTick(ctx context.Context) {
	tasks, err := s.loadTasks(ctx, "named_event")
	if err != nil {
		slog.Error("ecosystem service: loading named_event tasks failed", "error", err)
		return
	}
	if len(tasks) == 0 {
		return
	}

	wallets, err := s.playerWallets(ctx)
	if err != nil {
		slog.Error("ecosystem service: loading player wallets failed", "error", err)
		return
	}
	walletByTopic := make(map[common.Hash]string, len(wallets))
	for _, w := range wallets {
		walletByTopic[common.BytesToHash(common.HexToAddress(w).Bytes())] = w
	}

	latest, err := s.chain.LatestBlock(ctx)
	if err != nil {
		slog.Error("ecosystem service: fetching latest block failed", "error", err)
		return
	}

	for _, task := range tasks {
		if task.contractAddress == nil || task.eventTopic0 == nil || task.walletTopicIndex == nil {
			continue // not fully configured
		}
		match := matchNamedEvent(common.HexToHash(*task.eventTopic0), *task.walletTopicIndex)
		s.indexContractEvent(ctx, task, *task.contractAddress, latest, walletByTopic, match)
	}
}

func (s *Service) ensurePlayer(ctx context.Context, wallet string) error {
	_, err := s.db.Exec(ctx, `
		INSERT INTO players (wallet_address) VALUES ($1)
		ON CONFLICT (wallet_address) DO NOTHING`, wallet)
	return err
}

func (s *Service) loadCursor(ctx context.Context, key string, deployBlock uint64) (uint64, error) {
	var last int64
	err := s.db.QueryRow(ctx, `SELECT last_block FROM indexer_cursor WHERE contract_name = $1`, key).Scan(&last)
	if err != nil {
		return deployBlock, nil
	}
	return uint64(last), nil
}

func (s *Service) saveCursor(ctx context.Context, key string, block uint64) error {
	_, err := s.db.Exec(ctx, `
		INSERT INTO indexer_cursor (contract_name, last_block) VALUES ($1, $2)
		ON CONFLICT (contract_name) DO UPDATE SET last_block = $2`, key, int64(block))
	return err
}
