// Package marketplace implements the Marketplace Indexer: polls Marketplace.sol for
// Listed/Sold/Cancelled events, decodes them, and mirrors them into the `listings` Postgres
// table so the REST API (and the Flutter app) can query cheaply instead of hitting the RPC node
// for every marketplace browse.
package marketplace

import (
	"context"
	"fmt"
	"log/slog"
	"math/big"
	"time"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/jackc/pgx/v5/pgxpool"
)

const cursorKey = "Marketplace"

// LogFilterer is satisfied by internal/chain.Client.
type LogFilterer interface {
	FilterMarketplaceLogs(ctx context.Context, fromBlock, toBlock uint64) ([]types.Log, error)
	MarketplaceABI() abi.ABI
	LatestBlock(ctx context.Context) (uint64, error)
	BlockTime(ctx context.Context, blockNumber uint64) (time.Time, error)
}

// ProgressRecorder is satisfied by internal/services/task.Service.
type ProgressRecorder interface {
	RecordProgressAt(ctx context.Context, wallet, taskID string, delta int, at time.Time) error
}

// Notifier is satisfied by internal/realtime.Hub. Optional (nil-safe) so the indexer still works
// in tests/tools that don't wire up a hub.
type Notifier interface {
	Notify(wallet string, eventType string, payload any)
	Broadcast(eventType string, payload any)
}

type Indexer struct {
	db          *pgxpool.Pool
	chain       LogFilterer
	tasks       ProgressRecorder
	hub         Notifier
	deployBlock uint64
	batchSize   uint64

	eggNFTAddress      string
	creatureNFTAddress string

	// Reset each tick; see gamestate.Indexer's identical field for why.
	blockTimeCache map[uint64]time.Time
}

func NewIndexer(db *pgxpool.Pool, chain LogFilterer, tasks ProgressRecorder, hub Notifier, deployBlock uint64, eggNFTAddress, creatureNFTAddress string) *Indexer {
	return &Indexer{
		db:                 db,
		chain:              chain,
		tasks:              tasks,
		hub:                hub,
		deployBlock:        deployBlock,
		batchSize:          2000,
		eggNFTAddress:      common.HexToAddress(eggNFTAddress).Hex(),
		creatureNFTAddress: common.HexToAddress(creatureNFTAddress).Hex(),
	}
}

func (idx *Indexer) notify(wallet, eventType string, payload any) {
	if idx.hub == nil {
		return
	}
	idx.hub.Notify(wallet, eventType, payload)
}

func (idx *Indexer) broadcast(eventType string, payload any) {
	if idx.hub == nil {
		return
	}
	idx.hub.Broadcast(eventType, payload)
}

func (idx *Indexer) blockTime(ctx context.Context, blockNumber uint64) (time.Time, error) {
	if t, ok := idx.blockTimeCache[blockNumber]; ok {
		return t, nil
	}
	t, err := idx.chain.BlockTime(ctx, blockNumber)
	if err != nil {
		return time.Time{}, err
	}
	idx.blockTimeCache[blockNumber] = t
	return t, nil
}

// Run polls for new blocks every interval until ctx is cancelled.
func (idx *Indexer) Run(ctx context.Context, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	idx.tick(ctx)
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			idx.tick(ctx)
		}
	}
}

func (idx *Indexer) tick(ctx context.Context) {
	from, err := idx.cursor(ctx)
	if err != nil {
		slog.Error("marketplace indexer: reading cursor failed", "error", err)
		return
	}

	latest, err := idx.chain.LatestBlock(ctx)
	if err != nil {
		slog.Error("marketplace indexer: fetching latest block failed", "error", err)
		return
	}
	if from > latest {
		return
	}

	idx.blockTimeCache = make(map[uint64]time.Time)

	for from <= latest {
		to := from + idx.batchSize
		if to > latest {
			to = latest
		}

		logs, err := idx.chain.FilterMarketplaceLogs(ctx, from, to)
		if err != nil {
			slog.Error("marketplace indexer: filtering logs failed", "from", from, "to", to, "error", err)
			return
		}

		for _, log := range logs {
			if err := idx.handleLogSafely(ctx, log); err != nil {
				slog.Error("marketplace indexer: handling log failed", "txHash", log.TxHash.Hex(), "error", err)
			}
		}

		if err := idx.saveCursor(ctx, to+1); err != nil {
			slog.Error("marketplace indexer: saving cursor failed", "error", err)
			return
		}
		from = to + 1
	}
}

// handleLogSafely recovers from a decode panic on a single malformed/unexpected log so it can't
// take down the whole indexer goroutine -- and by extension the server process, since nothing
// else in cmd/server recovers panics from background goroutines.
func (idx *Indexer) handleLogSafely(ctx context.Context, log types.Log) (err error) {
	defer func() {
		if r := recover(); r != nil {
			err = fmt.Errorf("panic handling log: %v", r)
		}
	}()
	return idx.handleLog(ctx, log)
}

func (idx *Indexer) handleLog(ctx context.Context, log types.Log) error {
	contractABI := idx.chain.MarketplaceABI()
	event, err := contractABI.EventByID(log.Topics[0])
	if err != nil {
		return nil // not one of our known events (shouldn't happen given the FilterQuery, but be safe)
	}

	switch event.Name {
	case "Listed":
		return idx.handleListed(ctx, contractABI, log)
	case "Sold":
		return idx.handleSold(ctx, contractABI, log)
	case "Cancelled":
		return idx.handleCancelled(ctx, contractABI, log)
	default:
		return nil
	}
}

func (idx *Indexer) handleListed(ctx context.Context, contractABI abi.ABI, log types.Log) error {
	data := map[string]interface{}{}
	if err := contractABI.UnpackIntoMap(data, "Listed", log.Data); err != nil {
		return fmt.Errorf("unpacking Listed data: %w", err)
	}
	if err := abi.ParseTopicsIntoMap(data, indexedArgs(contractABI, "Listed"), log.Topics[1:]); err != nil {
		return fmt.Errorf("parsing Listed topics: %w", err)
	}

	listingID := data["listingId"].(*big.Int).Int64()
	seller := data["seller"].(common.Address).Hex()
	nftContract := data["nftContract"].(common.Address).Hex()
	tokenID := data["tokenId"].(*big.Int).Int64()
	price := data["price"].(*big.Int).String()

	kind := "creature"
	if nftContract == idx.eggNFTAddress {
		kind = "egg"
	}

	listedAt, err := idx.blockTime(ctx, log.BlockNumber)
	if err != nil {
		return err
	}

	_, err = idx.db.Exec(ctx, `
		INSERT INTO listings (listing_id, nft_contract, token_id, kind, seller_address, price_wei, is_active, listed_at, tx_hash)
		VALUES ($1, $2, $3, $4, $5, $6, true, $7, $8)
		ON CONFLICT (listing_id) DO NOTHING`,
		listingID, nftContract, tokenID, kind, seller, price, listedAt, log.TxHash.Hex())
	if err != nil {
		return err
	}

	if idx.tasks != nil {
		if err := idx.tasks.RecordProgressAt(ctx, seller, "list_1_item", 1, listedAt); err != nil {
			slog.Error("marketplace indexer: recording task progress failed", "wallet", seller, "error", err)
		}
	}
	idx.broadcast("marketplace_changed", map[string]any{"listingId": listingID, "reason": "listed"})
	return nil
}

func (idx *Indexer) handleSold(ctx context.Context, contractABI abi.ABI, log types.Log) error {
	data := map[string]interface{}{}
	if err := contractABI.UnpackIntoMap(data, "Sold", log.Data); err != nil {
		return fmt.Errorf("unpacking Sold data: %w", err)
	}
	if err := abi.ParseTopicsIntoMap(data, indexedArgs(contractABI, "Sold"), log.Topics[1:]); err != nil {
		return fmt.Errorf("parsing Sold topics: %w", err)
	}

	listingID := data["listingId"].(*big.Int).Int64()
	buyer := data["buyer"].(common.Address).Hex()
	price := data["price"].(*big.Int)

	var seller string
	if err := idx.db.QueryRow(ctx, `
		UPDATE listings SET is_active = false, sold_at = now(), buyer_address = $2
		WHERE listing_id = $1 RETURNING seller_address`, listingID, buyer).Scan(&seller); err != nil {
		return err
	}

	priceStr := price.String()
	idx.recordWalletEvent(ctx, buyer, "listing_bought", fmt.Sprintf("You bought listing #%d for %s ETH", listingID, formatEtherApprox(price)), priceStr)
	idx.recordWalletEvent(ctx, seller, "listing_sold", fmt.Sprintf("Your listing #%d sold for %s ETH", listingID, formatEtherApprox(price)), priceStr)
	idx.broadcast("marketplace_changed", map[string]any{"listingId": listingID, "reason": "sold"})
	return nil
}

func (idx *Indexer) handleCancelled(ctx context.Context, contractABI abi.ABI, log types.Log) error {
	data := map[string]interface{}{}
	if err := abi.ParseTopicsIntoMap(data, indexedArgs(contractABI, "Cancelled"), log.Topics[1:]); err != nil {
		return fmt.Errorf("parsing Cancelled topics: %w", err)
	}
	listingID := data["listingId"].(*big.Int).Int64()

	_, err := idx.db.Exec(ctx, `
		UPDATE listings SET is_active = false, cancelled_at = now()
		WHERE listing_id = $1`, listingID)
	if err != nil {
		return err
	}
	idx.broadcast("marketplace_changed", map[string]any{"listingId": listingID, "reason": "cancelled"})
	return nil
}

// recordWalletEvent persists a wallet_events row and, if that wallet is currently connected,
// pushes it live over the websocket -- logged and swallowed on failure since it must never block
// the trade it's describing.
func (idx *Indexer) recordWalletEvent(ctx context.Context, wallet, kind, message, amountWei string) {
	// players.wallet_address is stored EIP-55 checksummed (see gamestate/ecosystem's ensurePlayer)
	// -- must insert the same casing or this violates wallet_events_wallet_address_fkey. Notify
	// itself is case-insensitive (the hub lowercases for its own lookup), so the checksummed form
	// works for both.
	checksummed := common.HexToAddress(wallet).Hex()
	if _, err := idx.db.Exec(ctx, `
		INSERT INTO wallet_events (wallet_address, kind, message, amount_wei) VALUES ($1, $2, $3, $4)`,
		checksummed, kind, message, amountWei); err != nil {
		slog.Error("marketplace indexer: recording wallet event failed", "wallet", wallet, "error", err)
	}
	idx.notify(checksummed, "wallet_event", map[string]any{
		"kind":      kind,
		"message":   message,
		"amountWei": amountWei,
	})
}

// formatEtherApprox renders wei as an ETH string to 5 decimal places for a notification message.
func formatEtherApprox(wei *big.Int) string {
	f := new(big.Float).SetInt(wei)
	f.Quo(f, big.NewFloat(1e18))
	return f.Text('f', 5)
}

func (idx *Indexer) cursor(ctx context.Context) (uint64, error) {
	var last int64
	err := idx.db.QueryRow(ctx, `SELECT last_block FROM indexer_cursor WHERE contract_name = $1`, cursorKey).Scan(&last)
	if err != nil {
		// No row yet: start from the contract's deploy block.
		return idx.deployBlock, nil
	}
	return uint64(last), nil
}

func (idx *Indexer) saveCursor(ctx context.Context, block uint64) error {
	_, err := idx.db.Exec(ctx, `
		INSERT INTO indexer_cursor (contract_name, last_block) VALUES ($1, $2)
		ON CONFLICT (contract_name) DO UPDATE SET last_block = $2`, cursorKey, int64(block))
	return err
}

// indexedArgs returns the subset of an event's ABI inputs that are indexed (i.e. stored in log
// topics rather than log data), in declaration order -- what abi.ParseTopicsIntoMap expects.
func indexedArgs(contractABI abi.ABI, eventName string) abi.Arguments {
	var args abi.Arguments
	for _, input := range contractABI.Events[eventName].Inputs {
		if input.Indexed {
			args = append(args, input)
		}
	}
	return args
}
