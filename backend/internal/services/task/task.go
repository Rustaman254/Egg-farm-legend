// Package task implements the Task Service: tracks per-player daily task progress, and
// distributes $FEED rewards on completion via the chain client's MINTER_ROLE signer. Progress
// resets daily at 00:00 UTC because task_progress rows are keyed by (wallet, task, UTC date).
package task

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"log/slog"
	"math/big"
	"regexp"
	"strings"
	"time"

	"github.com/eggfarm/backend/internal/models"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrTaskNotFound       = errors.New("task not found")
	ErrNotCompleted       = errors.New("task not yet completed")
	ErrAlreadyClaimed     = errors.New("reward already claimed")
	ErrTaskNotFunded      = errors.New("this quest's creator hasn't funded enough $FEED to cover this reward yet")
	ErrNotPartnerTask     = errors.New("only partner/protocol quests can be funded")
	ErrPaymentUnverified  = errors.New("couldn't verify that payment on-chain")
	ErrPaymentAlreadyUsed = errors.New("that payment has already been credited")
)

// FeedMinter is satisfied by internal/chain.Client. Kept as a narrow interface here so the task
// package doesn't need to import go-ethereum.
type FeedMinter interface {
	MintReward(ctx context.Context, to string, amount *big.Int) (txHash string, err error)
}

// BlockReader is satisfied by internal/chain.Client.
type BlockReader interface {
	LatestBlock(ctx context.Context) (uint64, error)
}

// PaymentVerifier is satisfied by internal/chain.Client. Confirms a protocol's "buy $FEED to fund
// a quest" payment actually landed on the treasury address, and returns how much native currency
// it paid -- read from the chain itself, never trusted from the request.
type PaymentVerifier interface {
	VerifyNativePayment(ctx context.Context, txHash, to string) (*big.Int, error)
}

type Service struct {
	db                *pgxpool.Pool
	minter            FeedMinter
	chain             BlockReader
	payments          PaymentVerifier
	treasury          string
	feedPerNativeUnit int64
}

func NewService(db *pgxpool.Pool, minter FeedMinter, chain BlockReader, payments PaymentVerifier, treasury string, feedPerNativeUnit int64) *Service {
	return &Service{db: db, minter: minter, chain: chain, payments: payments, treasury: treasury, feedPerNativeUnit: feedPerNativeUnit}
}

func today() time.Time {
	return dateOf(time.Now())
}

func dateOf(t time.Time) time.Time {
	u := t.UTC()
	return time.Date(u.Year(), u.Month(), u.Day(), 0, 0, 0, 0, time.UTC)
}

// ListTasks returns today's task catalog with this player's current progress, creating
// zero-progress rows on the fly so the Flutter app always has something to render. Expired
// partner quests drop out of the active list automatically (no cron sweep needed) once
// expires_at has passed.
func (s *Service) ListTasks(ctx context.Context, wallet string) ([]models.TaskProgress, error) {
	rows, err := s.db.Query(ctx, `
		SELECT t.id, t.title, t.description, t.category, t.creator_address, t.check_type,
		       t.contract_address, t.function_signature, t.event_signature, t.expires_at,
		       t.target_count, t.reward_feed, t.funded_feed,
		       COALESCE(tp.current_count, 0), tp.completed_at, COALESCE(tp.reward_claimed, false)
		FROM tasks t
		LEFT JOIN task_progress tp
		  ON tp.task_id = t.id AND tp.wallet_address = $1 AND tp.progress_date = $2
		WHERE t.is_active AND (t.expires_at IS NULL OR t.expires_at > now())
		ORDER BY t.category, t.id`, wallet, today())
	if err != nil {
		return nil, fmt.Errorf("listing tasks: %w", err)
	}
	defer rows.Close()

	var out []models.TaskProgress
	for rows.Next() {
		var tp models.TaskProgress
		if err := rows.Scan(&tp.TaskID, &tp.Title, &tp.Description, &tp.Category, &tp.CreatorAddress, &tp.CheckType,
			&tp.ContractAddress, &tp.FunctionSignature, &tp.EventSignature, &tp.ExpiresAt, &tp.TargetCount, &tp.RewardFeed, &tp.FundedFeed,
			&tp.CurrentCount, &tp.CompletedAt, &tp.RewardClaimed); err != nil {
			return nil, err
		}
		out = append(out, tp)
	}
	return out, rows.Err()
}

// RecordProgress increments a task's counter for today. Prefer RecordProgressAt when the
// progress originates from an on-chain event, which carries its own timestamp.
func (s *Service) RecordProgress(ctx context.Context, wallet, taskID string, delta int) error {
	return s.RecordProgressAt(ctx, wallet, taskID, delta, time.Now())
}

// RecordProgressAt increments a task's counter for the UTC day of `at` -- e.g. called by the
// game-state/marketplace indexers after a CreatureFed, EggLaid, or Listed event confirms, using
// that event's actual block timestamp so progress attributes to the day the action happened
// rather than the day the indexer happened to catch up on a backlog. Marks completed_at once
// target_count is reached.
func (s *Service) RecordProgressAt(ctx context.Context, wallet, taskID string, delta int, at time.Time) error {
	var target int
	if err := s.db.QueryRow(ctx, `SELECT target_count FROM tasks WHERE id = $1 AND is_active`, taskID).Scan(&target); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrTaskNotFound
		}
		return err
	}

	// $4/$5 are cast explicitly at every occurrence: reusing a placeholder in both a plain
	// VALUES-list position and an expression (e.g. `$4 >= $5`) defeats Postgres's parameter
	// type inference ("inconsistent types deduced for parameter $4") when the driver doesn't
	// send explicit param type OIDs, which pgx doesn't by default.
	_, err := s.db.Exec(ctx, `
		INSERT INTO task_progress (wallet_address, task_id, progress_date, current_count, completed_at)
		VALUES ($1, $2, $3, $4::int, CASE WHEN $4::int >= $5::int THEN now() ELSE NULL END)
		ON CONFLICT (wallet_address, task_id, progress_date) DO UPDATE
		SET current_count = LEAST(task_progress.current_count + $4::int, $5::int),
		    completed_at = CASE
		        WHEN task_progress.completed_at IS NOT NULL THEN task_progress.completed_at
		        WHEN task_progress.current_count + $4::int >= $5::int THEN now()
		        ELSE NULL
		    END`,
		wallet, taskID, dateOf(at), delta, target)
	return err
}

// ClaimReward mints the task's $FEED reward to the player once, on completion. A built-in task
// (no creator_address) always pays out -- it's the core game loop, not something anyone funds.
// A partner/protocol quest only pays out while its creator has funded enough $FEED to cover it
// (see FundTask); the funded balance is drawn down by exactly the reward on every claim.
func (s *Service) ClaimReward(ctx context.Context, wallet, taskID string) (txHash string, err error) {
	var completedAt *time.Time
	var claimed bool
	var rewardFeed string
	var creatorAddress *string
	err = s.db.QueryRow(ctx, `
		SELECT tp.completed_at, tp.reward_claimed, t.reward_feed, t.creator_address
		FROM task_progress tp
		JOIN tasks t ON t.id = tp.task_id
		WHERE tp.wallet_address = $1 AND tp.task_id = $2 AND tp.progress_date = $3`,
		wallet, taskID, today()).Scan(&completedAt, &claimed, &rewardFeed, &creatorAddress)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", ErrNotCompleted
		}
		return "", err
	}
	if completedAt == nil {
		return "", ErrNotCompleted
	}
	if claimed {
		return "", ErrAlreadyClaimed
	}

	amount, ok := new(big.Int).SetString(rewardFeed, 10)
	if !ok {
		return "", fmt.Errorf("invalid reward_feed value %q for task %s", rewardFeed, taskID)
	}

	if creatorAddress != nil {
		var funded string
		if err := s.db.QueryRow(ctx, `SELECT funded_feed FROM tasks WHERE id = $1`, taskID).Scan(&funded); err != nil {
			return "", fmt.Errorf("checking quest funding: %w", err)
		}
		fundedAmount, ok := new(big.Int).SetString(funded, 10)
		if !ok || fundedAmount.Cmp(amount) < 0 {
			return "", ErrTaskNotFunded
		}
	}

	txHash, err = s.minter.MintReward(ctx, wallet, amount)
	if err != nil {
		return "", fmt.Errorf("minting reward: %w", err)
	}

	if creatorAddress != nil {
		// Best-effort draw-down after a successful mint -- checked-then-acted rather than atomic
		// with the mint (an on-chain tx can't participate in a DB transaction), so a pathological
		// race between two simultaneous claims on the last sliver of funding could very rarely
		// let a claim through with funded_feed dipping negative; DB CHECK isn't used here for the
		// same reason ClaimReward already isn't wrapped in a single atomic guard elsewhere.
		if _, err := s.db.Exec(ctx, `UPDATE tasks SET funded_feed = GREATEST(0, funded_feed - $2) WHERE id = $1`, taskID, rewardFeed); err != nil {
			slog.Error("drawing down quest funding failed", "taskId", taskID, "error", err)
		}
	}

	// Farmer XP is awarded 1:1 with the whole $FEED amount -- every task claim doubles as
	// progress toward the next Farmer level, no separate balancing knob needed.
	xp := new(big.Int).Div(amount, big.NewInt(1e18)).Int64()
	if _, err := s.db.Exec(ctx, `UPDATE players SET xp = xp + $2 WHERE wallet_address = $1`, wallet, xp); err != nil {
		return "", fmt.Errorf("awarding XP: %w", err)
	}

	_, err = s.db.Exec(ctx, `
		UPDATE task_progress SET reward_claimed = true
		WHERE wallet_address = $1 AND task_id = $2 AND progress_date = $3`,
		wallet, taskID, today())
	return txHash, err
}

// FundTask credits a partner quest's reward pool after verifying the protocol actually paid the
// platform treasury on-chain -- this is both how a protocol supplies the $FEED its quest will pay
// out, and how the platform earns from partner quests existing at all (the native-currency
// payment lands in TreasuryAddress; see internal/chain.Client.VerifyNativePayment). txHash can
// only ever be credited once (platform_revenue.tx_hash is unique).
func (s *Service) FundTask(ctx context.Context, taskID, funderAddress, txHash string) (feedCredited *big.Int, err error) {
	if s.treasury == "" {
		return nil, fmt.Errorf("no treasury address configured")
	}
	var creatorAddress *string
	if err := s.db.QueryRow(ctx, `SELECT creator_address FROM tasks WHERE id = $1`, taskID).Scan(&creatorAddress); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrTaskNotFound
		}
		return nil, err
	}
	if creatorAddress == nil {
		return nil, ErrNotPartnerTask
	}

	paidWei, err := s.payments.VerifyNativePayment(ctx, txHash, s.treasury)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrPaymentUnverified, err)
	}

	// 1 native unit (ARB/ETH, 18 decimals) buys feedPerNativeUnit whole $FEED (18 decimals too),
	// so the conversion is just a straight multiply -- both sides share the same decimal base.
	feedCredited = new(big.Int).Mul(paidWei, big.NewInt(s.feedPerNativeUnit))

	tag, err := s.db.Exec(ctx, `
		INSERT INTO platform_revenue (source, wallet_address, tx_hash, native_amount_wei, feed_amount, task_id)
		VALUES ('quest_funding', $1, $2, $3, $4, $5)
		ON CONFLICT (tx_hash) WHERE tx_hash IS NOT NULL DO NOTHING`,
		funderAddress, txHash, paidWei.String(), feedCredited.String(), taskID)
	if err != nil {
		return nil, fmt.Errorf("recording quest funding: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return nil, ErrPaymentAlreadyUsed
	}

	if _, err := s.db.Exec(ctx, `UPDATE tasks SET funded_feed = funded_feed + $2 WHERE id = $1`, taskID, feedCredited.String()); err != nil {
		return nil, fmt.Errorf("crediting quest funding: %w", err)
	}
	return feedCredited, nil
}

// RecordDailyLogin bumps the player's login streak and marks the daily_login task complete.
func (s *Service) RecordDailyLogin(ctx context.Context, wallet string) error {
	_, err := s.db.Exec(ctx, `
		INSERT INTO players (wallet_address, last_login_at, login_streak_days)
		VALUES ($1, now(), 1)
		ON CONFLICT (wallet_address) DO UPDATE
		SET login_streak_days = CASE
		        WHEN players.last_login_at IS NULL OR players.last_login_at < now() - interval '2 days'
		            THEN 1
		        WHEN players.last_login_at::date = now()::date
		            THEN players.login_streak_days
		        ELSE players.login_streak_days + 1
		    END,
		    last_login_at = now()`, wallet)
	if err != nil {
		return err
	}
	return s.RecordProgress(ctx, wallet, "daily_login", 1)
}

// Bounds enforced on every partner/community quest -- permissionless creation with no review
// queue only works if a single bad actor can't drain the $FEED supply or flood the quest board.
const (
	MaxPartnerRewardFeedWhole = 50 // whole $FEED per completion
	MaxPartnerTargetCount     = 10
	MaxPartnerDurationDays    = 30
	MinPartnerDurationDays    = 1
)

// partnerCheckTypes: the five ways a Community Quest can prove a player did something, from most
// to least specific to a hand-picked token:
//
//	token_balance  -- hold >= N of a token/NFT (ERC-20/721 balanceOf)
//	token_received -- received a transfer of a token (Transfer event `to`)
//	view_function  -- ANY `fn(address) returns (T)` read, compared to a threshold -- staked
//	                  balance, points, reputation, tier, "isMember", or anything else a protocol
//	                  exposes per-wallet. This is what makes quest creation work for a protocol
//	                  that isn't shaped like a token at all.
//	named_event    -- ANY specific event, matched by exact signature (not just "any event" like
//	                  contract_event below) with the wallet in a creator-chosen indexed slot --
//	                  "prove you called *this* function", not just "prove you touched this
//	                  contract at all".
//	contract_event -- wallet appears in any indexed topic of any event the contract emits; the
//	                  broadest, least precise option, useful when a creator doesn't know/care
//	                  which specific event proves engagement.
var partnerCheckTypes = map[string]bool{
	"token_balance":  true,
	"token_received": true,
	"view_function":  true,
	"named_event":    true,
	"contract_event": true,
}

var allowedOutputTypes = map[string]bool{
	"uint8": true, "uint16": true, "uint32": true, "uint64": true, "uint128": true, "uint256": true, "bool": true,
}

// functionSigPattern matches a Solidity-style call signature with exactly one `address`
// argument, e.g. "stakedAmount(address)" -- the only shape view_function supports, since the
// wallet being checked is always the sole argument.
var functionSigPattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*\(address\)$`)

// eventSigPattern matches a canonical Solidity event signature (types only, no param names or
// `indexed` keywords -- exactly the form used to compute an event's topic0), e.g.
// "Staked(address,uint256)".
var eventSigPattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*\([A-Za-z0-9_,\[\]]*\)$`)

var (
	ErrInvalidCheckType = errors.New(
		"checkType must be one of: token_balance, token_received, view_function, named_event, contract_event")
	ErrInvalidContract    = errors.New("contractAddress must be a valid 0x-prefixed 20-byte address")
	ErrRewardTooHigh      = fmt.Errorf("rewardFeedWhole must be between 1 and %d", MaxPartnerRewardFeedWhole)
	ErrTargetOutOfRange   = fmt.Errorf("targetCount must be between 1 and %d", MaxPartnerTargetCount)
	ErrDurationOutOfRange = fmt.Errorf(
		"durationDays must be between %d and %d", MinPartnerDurationDays, MaxPartnerDurationDays)
)

type CreateTaskInput struct {
	CreatorAddress  string
	Title           string
	Description     string
	CheckType       string
	ContractAddress string
	ThresholdWei    string // required for token_balance and numeric-output view_function checks

	FunctionSignature string // view_function: e.g. "stakedAmount(address)"
	OutputType        string // view_function: uint8|uint16|uint32|uint64|uint128|uint256|bool

	EventSignature   string // named_event: canonical form, e.g. "Staked(address,uint256)"
	WalletTopicIndex int    // named_event: 1, 2, or 3 -- which indexed param is the wallet

	TargetCount     int
	RewardFeedWhole int
	DurationDays    int
}

// isHexAddress mirrors go-ethereum's common.IsHexAddress without importing go-ethereum into this
// package (kept dependency-free of the chain package on purpose -- see FeedMinter above).
func isHexAddress(s string) bool {
	if len(s) != 42 || s[0] != '0' || (s[1] != 'x' && s[1] != 'X') {
		return false
	}
	for _, c := range s[2:] {
		if !(c >= '0' && c <= '9') && !(c >= 'a' && c <= 'f') && !(c >= 'A' && c <= 'F') {
			return false
		}
	}
	return true
}

// CreateTask lets any wallet define a new "partner" quest rewarding activity on a protocol they
// name -- no approval step, since reward/target/duration are hard-capped instead. Verification
// reuses the same check_type machinery as the curated 'ecosystem' tasks (see internal/services/
// ecosystem), just pointed at whatever contract the creator specifies rather than one we curate.
func (s *Service) CreateTask(ctx context.Context, in CreateTaskInput) (taskID string, err error) {
	if in.Title == "" || len(in.Title) > 80 {
		return "", errors.New("title must be 1-80 characters")
	}
	if in.Description == "" || len(in.Description) > 280 {
		return "", errors.New("description must be 1-280 characters")
	}
	if !partnerCheckTypes[in.CheckType] {
		return "", ErrInvalidCheckType
	}
	if !isHexAddress(in.ContractAddress) {
		return "", ErrInvalidContract
	}
	if in.RewardFeedWhole < 1 || in.RewardFeedWhole > MaxPartnerRewardFeedWhole {
		return "", ErrRewardTooHigh
	}
	if in.TargetCount < 1 || in.TargetCount > MaxPartnerTargetCount {
		return "", ErrTargetOutOfRange
	}
	if in.DurationDays < MinPartnerDurationDays || in.DurationDays > MaxPartnerDurationDays {
		return "", ErrDurationOutOfRange
	}

	var thresholdWei *string
	setThreshold := func() error {
		amount, ok := new(big.Int).SetString(in.ThresholdWei, 10)
		if !ok || amount.Sign() <= 0 {
			return errors.New("thresholdWei must be a positive integer string")
		}
		s := amount.String()
		thresholdWei = &s
		return nil
	}

	var functionSignature, functionSelector, outputType *string
	var eventSignature, eventTopic0 *string
	var walletTopicIndex *int

	switch in.CheckType {
	case "token_balance":
		if err := setThreshold(); err != nil {
			return "", fmt.Errorf("%w for token_balance quests", err)
		}

	case "view_function":
		sig := strings.ReplaceAll(in.FunctionSignature, " ", "")
		if !functionSigPattern.MatchString(sig) {
			return "", errors.New(`functionSignature must look like "name(address)" -- exactly one address argument`)
		}
		if !allowedOutputTypes[in.OutputType] {
			return "", errors.New("outputType must be one of: uint8, uint16, uint32, uint64, uint128, uint256, bool")
		}
		if in.OutputType != "bool" {
			if err := setThreshold(); err != nil {
				return "", fmt.Errorf("%w for a numeric-output view_function quest", err)
			}
		}
		selector := hex.EncodeToString(crypto.Keccak256([]byte(sig))[:4])
		functionSignature = &sig
		functionSelector = &selector
		out := in.OutputType
		outputType = &out

	case "named_event":
		sig := strings.ReplaceAll(in.EventSignature, " ", "")
		if !eventSigPattern.MatchString(sig) {
			return "", errors.New(`eventSignature must be the canonical form, e.g. "Staked(address,uint256)"`)
		}
		if in.WalletTopicIndex < 1 || in.WalletTopicIndex > 3 {
			return "", errors.New("walletTopicIndex must be 1, 2, or 3 (which indexed parameter is the wallet)")
		}
		topic0 := crypto.Keccak256Hash([]byte(sig)).Hex()
		eventSignature = &sig
		eventTopic0 = &topic0
		idx := in.WalletTopicIndex
		walletTopicIndex = &idx
	}

	idBytes := make([]byte, 4)
	if _, err := rand.Read(idBytes); err != nil {
		return "", fmt.Errorf("generating task id: %w", err)
	}
	taskID = "partner_" + hex.EncodeToString(idBytes)

	rewardFeed := new(big.Int).Mul(big.NewInt(int64(in.RewardFeedWhole)), big.NewInt(1e18))
	expiresAt := time.Now().Add(time.Duration(in.DurationDays) * 24 * time.Hour)

	// Quests count activity from creation time forward, not retroactively -- so a new task never
	// has to backfill-scan a protocol's entire history, which could be millions of blocks on a
	// contract that's been live for a while.
	var deployBlock uint64
	if in.CheckType == "token_received" || in.CheckType == "contract_event" || in.CheckType == "named_event" {
		deployBlock, err = s.chain.LatestBlock(ctx)
		if err != nil {
			return "", fmt.Errorf("reading latest block: %w", err)
		}
	}

	_, err = s.db.Exec(ctx, `
		INSERT INTO tasks (id, title, description, target_count, reward_feed, category, creator_address,
		                    check_type, contract_address, threshold_wei, expires_at, deploy_block,
		                    function_signature, function_selector, output_type,
		                    event_signature, event_topic0, wallet_topic_index)
		VALUES ($1, $2, $3, $4, $5, 'partner', $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17)`,
		taskID, in.Title, in.Description, in.TargetCount, rewardFeed.String(), in.CreatorAddress,
		in.CheckType, in.ContractAddress, thresholdWei, expiresAt, int64(deployBlock),
		functionSignature, functionSelector, outputType, eventSignature, eventTopic0, walletTopicIndex)
	if err != nil {
		return "", fmt.Errorf("creating task: %w", err)
	}
	return taskID, nil
}
