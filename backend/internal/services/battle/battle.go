// Package battle implements the Battle Arena: PvE duels against a procedurally-generated wild
// opponent, and PvP duels between two players' real creatures via an open challenge board. Not
// on-chain (a coin-flip-with-flavor doesn't need gas), but wins mint real $FEED and award Farmer
// XP through the same MINTER_ROLE signer path as tasks, and feed the `play_minigame` daily task.
package battle

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"math/big"
	"math/rand"
	"strings"
	"time"

	"github.com/eggfarm/backend/internal/models"
	"github.com/eggfarm/backend/internal/services/task"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrCreatureNotFound  = errors.New("creature not found")
	ErrNotOwner          = errors.New("you do not own this creature")
	ErrCreatureDead      = errors.New("that creature has starved and can no longer battle")
	ErrChallengeNotFound = errors.New("challenge not found")
	ErrChallengeNotOpen  = errors.New("challenge is no longer open")
	ErrChallengeExpired  = errors.New("challenge has expired")
	ErrOwnChallenge      = errors.New("you can't accept your own challenge")
	ErrNotChallenger     = errors.New("only the challenger can cancel this challenge")
	ErrNotTargeted       = errors.New("this challenge isn't addressed to you")
	ErrInvalidWager      = errors.New("invalid wager amount")
	ErrEscrowNotFunded   = errors.New("the on-chain wager escrow isn't funded yet")
	ErrEscrowMismatch    = errors.New("the on-chain escrow doesn't match this challenge")
)

// maxWagerWei caps a PvP wager at 1 ETH/ARB -- native currency has real value (unlike $FEED,
// which is an uncapped faucet token), so this bounds exposure on a local test network / early
// deployment rather than trusting players' judgment alone.
var maxWagerWei = new(big.Int).Mul(big.NewInt(1), big.NewInt(1e18))

// FeedMinter is satisfied by internal/chain.Client. Mints PvE/PvP $FEED rewards -- unrelated to
// wagers now that those are a native-currency on-chain escrow (see EscrowClient below).
type FeedMinter interface {
	MintReward(ctx context.Context, to string, amount *big.Int) (txHash string, err error)
}

// EscrowClient is satisfied by internal/chain.Client. Wraps BattleEscrow.sol: a trustless
// native-currency (ETH/ARB) escrow for PvP wagers -- see contracts/src/BattleEscrow.sol. The
// backend never custodies a wager itself; it only reads the escrow's on-chain state to confirm a
// stake actually landed, and (once combat is resolved) calls resolve() to release the pot.
type EscrowClient interface {
	GetEscrow(ctx context.Context, challengeID int64) (challenger, acceptor string, wagerWei *big.Int, status uint8, err error)
	ResolveEscrow(ctx context.Context, challengeID int64, winner string) (txHash string, err error)
	CancelEscrowOnChain(ctx context.Context, challengeID int64) (txHash string, err error)
}

// escrowStatusOpen/Accepted mirror BattleEscrow.sol's Status enum (None=0, Open=1, Accepted=2,
// Resolved=3, Cancelled=4).
const (
	escrowStatusOpen     = 1
	escrowStatusAccepted = 2
)

// Notifier pushes a live event to a wallet's arena websocket connection, if it has one open.
// Satisfied by internal/realtime.Hub; nil is fine (Service just skips the push) since a Service
// built without one degrades to the pre-websocket, poll-only behavior.
type Notifier interface {
	Notify(wallet string, eventType string, payload any)
}

type Service struct {
	db       *pgxpool.Pool
	minter   FeedMinter
	tasks    *task.Service
	hub      Notifier
	treasury string
	escrow   EscrowClient
}

func NewService(db *pgxpool.Pool, minter FeedMinter, tasks *task.Service, hub Notifier, treasury string, escrow EscrowClient) *Service {
	return &Service{db: db, minter: minter, tasks: tasks, hub: hub, treasury: treasury, escrow: escrow}
}

// wagerRakeBps mirrors BattleEscrow.sol's default rakeBps (500 = 5%) -- the contract is the
// actual source of truth for what gets deducted (it's the one that splits the pot on-chain);
// this is only used to compute what to *log* to platform_revenue for the activity feed.
const wagerRakeBps = 500

// recordRevenue logs a platform earning to platform_revenue for audit -- logged and swallowed on
// failure since it must never block the mint/settlement/resolve it's describing.
func (s *Service) recordRevenue(ctx context.Context, source, wallet string, nativeAmountWei *big.Int) {
	if _, err := s.db.Exec(ctx, `
		INSERT INTO platform_revenue (source, wallet_address, native_amount_wei) VALUES ($1, $2, $3)`,
		source, wallet, nativeAmountWei.String()); err != nil {
		slog.Error("recording platform revenue failed", "source", source, "wallet", wallet, "error", err)
	}
}

func (s *Service) notify(wallet, eventType string, payload any) {
	if s.hub == nil {
		return
	}
	s.hub.Notify(wallet, eventType, payload)
}

type Result struct {
	Won               bool     `json:"won"`
	PlayerSpecies     int      `json:"playerSpecies"`
	PlayerLevel       int      `json:"playerLevel"`
	PlayerHP          int      `json:"playerHp"`
	PlayerMaxHP       int      `json:"playerMaxHp"`
	PlayerAbilities   []string `json:"playerAbilities,omitempty"`
	OpponentSpecies   int      `json:"opponentSpecies"`
	OpponentRarity    int      `json:"opponentRarity"`
	OpponentLevel     int      `json:"opponentLevel"`
	OpponentHP        int      `json:"opponentHp"`
	OpponentMaxHP     int      `json:"opponentMaxHp"`
	OpponentAbilities []string `json:"opponentAbilities,omitempty"`
	Rounds            int      `json:"rounds"`
	Log               []string `json:"log"`
	RewardFeed        string   `json:"rewardFeed"`
	XPAwarded         int      `json:"xpAwarded"`
	TxHash            string   `json:"txHash,omitempty"`
	WagerWei          string   `json:"wagerWei,omitempty"`        // what each side staked (native currency), if this was a wagered PvP duel
	WagerWon          bool     `json:"wagerWon,omitempty"`        // true if Won and there was a wager on the line
	EscrowResolveTx   string   `json:"escrowResolveTx,omitempty"` // the on-chain tx that paid out the wager pot
}

type HistoryEntry struct {
	CreatureTokenID int64     `json:"creatureTokenId"`
	OpponentSpecies int16     `json:"opponentSpecies"`
	OpponentRarity  int16     `json:"opponentRarity"`
	Won             bool      `json:"won"`
	RewardFeed      string    `json:"rewardFeed"`
	CreatedAt       time.Time `json:"createdAt"`
}

// rewardForOpponent mirrors the task reward scale (10-50 FEED) so a battle win feels comparable
// to completing a task, weighted by how tough the opponent was. XP is awarded 1:1 with the whole
// FEED amount, so Farmer leveling needs no separate balancing pass.
func xpForOpponent(rarity int) int { return 15 * rarity }

func rewardForOpponent(rarity int) *big.Int {
	feed := big.NewInt(int64(xpForOpponent(rarity)))
	return feed.Mul(feed, big.NewInt(1e18))
}

func (s *Service) awardXP(ctx context.Context, wallet string, amount int) error {
	_, err := s.db.Exec(ctx, `UPDATE players SET xp = xp + $2 WHERE wallet_address = $1`, wallet, amount)
	return err
}

// simulate runs one deterministic-shape, randomized-damage duel: alternating attacks (player
// first) until someone's HP hits zero, or a 50-round cap to guarantee termination in a near-draw.
// Shared by PvE (Fight) and PvP (AcceptChallenge) -- a duel is a duel regardless of what the
// opponent's stats came from. playerMods/oppMods fold in each side's ability effects (lifesteal,
// thorns, berserker, first-strike); pass a zero-value CombatMods for a side with no abilities
// (e.g. a procedurally-generated wild PvE opponent).
func simulate(
	rng *rand.Rand,
	playerLabel string, playerHP, playerAtk, playerDef int, playerMods CombatMods,
	oppLabel string, oppHP, oppAtk, oppDef int, oppMods CombatMods,
) (finalPlayerHP, finalOppHP, rounds int, log []string) {
	pHP, oHP := playerHP, oppHP
	pMaxHP, oMaxHP := playerHP, oppHP
	log = make([]string, 0, 16)
	playerStruck, oppStruck := false, false

	for pHP > 0 && oHP > 0 && rounds < 50 {
		rounds++

		atk := playerAtk
		if playerMods.Berserker && pHP*100/pMaxHP < 30 {
			atk = atk * 5 / 4
		}
		dmg := atk - oppDef/2 + rng.Intn(7) - 3
		if dmg < 1 {
			dmg = 1
		}
		if playerMods.FirstStrike && !playerStruck {
			dmg *= 2
		}
		playerStruck = true
		oHP -= dmg
		suffix := ""
		if playerMods.Lifesteal > 0 {
			healed := int(float64(dmg) * playerMods.Lifesteal)
			if healed > 0 {
				pHP += healed
				if pHP > pMaxHP {
					pHP = pMaxHP
				}
				suffix += fmt.Sprintf(" (healed %d)", healed)
			}
		}
		if oppMods.Thorns > 0 {
			reflect := int(float64(dmg) * oppMods.Thorns)
			if reflect > 0 {
				pHP -= reflect
				suffix += fmt.Sprintf(" (took %d thorns)", reflect)
			}
		}
		log = append(log, fmt.Sprintf("%s hits for %d damage!%s", playerLabel, dmg, suffix))
		if oHP <= 0 {
			oHP = 0
			break
		}
		if pHP <= 0 {
			pHP = 0
			break
		}

		atk2 := oppAtk
		if oppMods.Berserker && oHP*100/oMaxHP < 30 {
			atk2 = atk2 * 5 / 4
		}
		dmg2 := atk2 - playerDef/2 + rng.Intn(7) - 3
		if dmg2 < 1 {
			dmg2 = 1
		}
		if oppMods.FirstStrike && !oppStruck {
			dmg2 *= 2
		}
		oppStruck = true
		pHP -= dmg2
		suffix2 := ""
		if oppMods.Lifesteal > 0 {
			healed := int(float64(dmg2) * oppMods.Lifesteal)
			if healed > 0 {
				oHP += healed
				if oHP > oMaxHP {
					oHP = oMaxHP
				}
				suffix2 += fmt.Sprintf(" (healed %d)", healed)
			}
		}
		if playerMods.Thorns > 0 {
			reflect := int(float64(dmg2) * playerMods.Thorns)
			if reflect > 0 {
				oHP -= reflect
				suffix2 += fmt.Sprintf(" (took %d thorns)", reflect)
			}
		}
		log = append(log, fmt.Sprintf("%s hits back for %d damage!%s", oppLabel, dmg2, suffix2))
		if pHP <= 0 {
			pHP = 0
			break
		}
		if oHP <= 0 {
			oHP = 0
			break
		}
	}
	return pHP, oHP, rounds, log
}

type creatureRow struct {
	species   int16
	rarity    int16
	careScore int
	owner     string
	isDead    bool
}

func (s *Service) loadCreature(ctx context.Context, tokenID int64) (*creatureRow, error) {
	var c creatureRow
	err := s.db.QueryRow(ctx,
		`SELECT species, rarity, care_score, owner_address, is_dead FROM creatures WHERE token_id = $1`, tokenID,
	).Scan(&c.species, &c.rarity, &c.careScore, &c.owner, &c.isDead)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrCreatureNotFound
		}
		return nil, fmt.Errorf("looking up creature: %w", err)
	}
	return &c, nil
}

func (s *Service) requireOwnedAliveCreature(ctx context.Context, wallet string, tokenID int64) (*creatureRow, error) {
	c, err := s.loadCreature(ctx, tokenID)
	if err != nil {
		return nil, err
	}
	if !strings.EqualFold(c.owner, wallet) {
		return nil, ErrNotOwner
	}
	if c.isDead {
		return nil, ErrCreatureDead
	}
	return c, nil
}

// Fight resolves one PvE duel: the player's creature (with its care-driven level applied) vs. a
// freshly rolled level-1 wild opponent within one rarity tier of it. A win mints $FEED, awards
// Farmer XP, and bumps play_minigame/win_3_battles progress.
func (s *Service) Fight(ctx context.Context, wallet string, creatureTokenID int64) (*Result, error) {
	c, err := s.requireOwnedAliveCreature(ctx, wallet, creatureTokenID)
	if err != nil {
		return nil, err
	}

	rng := rand.New(rand.NewSource(time.Now().UnixNano()))

	oppRarity := int(c.rarity) + []int{-1, 0, 0, 0, 1}[rng.Intn(5)]
	if oppRarity < 1 {
		oppRarity = 1
	}
	if oppRarity > 5 {
		oppRarity = 5
	}
	oppSpecies := (oppRarity-1)*8 + rng.Intn(8)

	pMaxHP, pAtk, pDef, pMods, pAbilityKeys, err := s.statsWithAbilities(ctx, creatureTokenID, int(c.species), int(c.rarity), c.careScore)
	if err != nil {
		return nil, err
	}
	oMaxHP, oAtk, oDef := BaseStats(oppSpecies, oppRarity) // wild opponents are always level 1 and have no abilities

	playerName := models.SpeciesName(c.species)
	oppName := models.SpeciesName(int16(oppSpecies))

	pHP, oHP, rounds, log := simulate(rng, "Your "+playerName, pMaxHP, pAtk, pDef, pMods, "Wild "+oppName, oMaxHP, oAtk, oDef, CombatMods{})

	won := pHP > oHP
	result := &Result{
		Won:             won,
		PlayerSpecies:   int(c.species),
		PlayerLevel:     LevelForCareScore(c.careScore),
		PlayerHP:        pHP,
		PlayerMaxHP:     pMaxHP,
		PlayerAbilities: pAbilityKeys,
		OpponentSpecies: oppSpecies,
		OpponentRarity:  oppRarity,
		OpponentLevel:   1,
		OpponentHP:      oHP,
		OpponentMaxHP:   oMaxHP,
		Rounds:          rounds,
		Log:             log,
	}

	rewardFeed := big.NewInt(0)
	if won {
		xp := xpForOpponent(oppRarity)
		rewardFeed = rewardForOpponent(oppRarity)
		txHash, err := s.minter.MintReward(ctx, wallet, rewardFeed)
		if err != nil {
			return nil, fmt.Errorf("minting battle reward: %w", err)
		}
		result.TxHash = txHash
		result.XPAwarded = xp
		if err := s.awardXP(ctx, wallet, xp); err != nil {
			return nil, fmt.Errorf("awarding XP: %w", err)
		}
		for _, taskID := range []string{"play_minigame", "win_3_battles"} {
			if err := s.tasks.RecordProgress(ctx, wallet, taskID, 1); err != nil && !errors.Is(err, task.ErrTaskNotFound) {
				return nil, fmt.Errorf("recording battle task progress: %w", err)
			}
		}
	}
	result.RewardFeed = rewardFeed.String()

	if err := s.recordBattleRow(ctx, wallet, creatureTokenID, int16(oppSpecies), int16(oppRarity), won, rounds, rewardFeed); err != nil {
		return nil, err
	}

	return result, nil
}

// History returns a wallet's most recent battles, newest first.
func (s *Service) History(ctx context.Context, wallet string, limit int) ([]HistoryEntry, error) {
	rows, err := s.db.Query(ctx, `
		SELECT creature_token_id, opponent_species, opponent_rarity, won, reward_feed, created_at
		FROM battles
		WHERE wallet_address = $1
		ORDER BY created_at DESC
		LIMIT $2`, wallet, limit)
	if err != nil {
		return nil, fmt.Errorf("listing battle history: %w", err)
	}
	defer rows.Close()

	out := []HistoryEntry{}
	for rows.Next() {
		var h HistoryEntry
		if err := rows.Scan(&h.CreatureTokenID, &h.OpponentSpecies, &h.OpponentRarity, &h.Won, &h.RewardFeed, &h.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, h)
	}
	return out, rows.Err()
}

// ---------------------------------------------------------------------
// Arena presence -- "who's in the arena right now"
// ---------------------------------------------------------------------

// Heartbeat marks a wallet as present in the arena; the Battle page pings this every ~20s while
// open. No websocket needed -- OnlineWallets just reads back whoever pinged recently.
func (s *Service) Heartbeat(ctx context.Context, wallet string) error {
	// A brand-new wallet may hit the arena before it's ever been recorded as a player elsewhere
	// (e.g. it never visited Tasks, which is where daily-login registration usually happens) --
	// arena_presence FKs into players, so make sure the row exists first.
	if _, err := s.db.Exec(ctx, `INSERT INTO players (wallet_address) VALUES ($1) ON CONFLICT DO NOTHING`, wallet); err != nil {
		return fmt.Errorf("ensuring player row: %w", err)
	}
	_, err := s.db.Exec(ctx, `
		INSERT INTO arena_presence (wallet_address, last_seen_at) VALUES ($1, now())
		ON CONFLICT (wallet_address) DO UPDATE SET last_seen_at = now()`, wallet)
	return err
}

type OnlinePlayer struct {
	Wallet   string `json:"wallet"`
	Battling bool   `json:"battling"` // has an active/open challenge right now
}

// OnlineWallets returns everyone seen in the arena in the last minute.
func (s *Service) OnlineWallets(ctx context.Context) ([]OnlinePlayer, error) {
	rows, err := s.db.Query(ctx, `
		SELECT p.wallet_address, EXISTS (
			SELECT 1 FROM battle_challenges c
			WHERE c.status = 'open' AND c.challenger_wallet = p.wallet_address
		)
		FROM arena_presence p
		WHERE p.last_seen_at > now() - interval '60 seconds'
		ORDER BY p.last_seen_at DESC`)
	if err != nil {
		return nil, fmt.Errorf("listing online wallets: %w", err)
	}
	defer rows.Close()

	out := []OnlinePlayer{}
	for rows.Next() {
		var o OnlinePlayer
		if err := rows.Scan(&o.Wallet, &o.Battling); err != nil {
			return nil, err
		}
		out = append(out, o)
	}
	return out, rows.Err()
}

// ---------------------------------------------------------------------
// PvP challenges -- the open challenge board
// ---------------------------------------------------------------------

type ChallengeSummary struct {
	ID                        int64    `json:"id"`
	ChallengerWallet          string   `json:"challengerWallet"`
	ChallengerCreatureTokenID int64    `json:"challengerCreatureTokenId"`
	ChallengerSpecies         int16    `json:"challengerSpecies"`
	ChallengerRarity          int16    `json:"challengerRarity"`
	ChallengerLevel           int      `json:"challengerLevel"`
	Status                    string   `json:"status"`
	ChallengedWallet          *string  `json:"challengedWallet,omitempty"` // set => a direct challenge, private to this wallet
	OpponentWallet            *string  `json:"opponentWallet,omitempty"`
	WinnerWallet              *string  `json:"winnerWallet,omitempty"`
	Rounds                    *int16   `json:"rounds,omitempty"`
	Log                       []string `json:"log,omitempty"`
	RewardFeed                *string  `json:"rewardFeed,omitempty"`
	WagerWei                  string   `json:"wagerWei"`
	// EscrowConfirmed is always true for an unwagered challenge; for a wagered one it's false
	// until the challenger's on-chain createEscrow() call is confirmed (see ConfirmEscrow) --
	// such a challenge is invisible to everyone but the challenger until then.
	EscrowConfirmed bool       `json:"escrowConfirmed"`
	CreatedAt       time.Time  `json:"createdAt"`
	ExpiresAt       time.Time  `json:"expiresAt"`
	ResolvedAt      *time.Time `json:"resolvedAt,omitempty"`
}

const (
	maxOpenChallengesPerWallet = 3
	challengeTTL               = 15 * time.Minute
)

// CreateChallenge posts a creature for a duel. With challengedWallet empty it goes on the public
// open board for anyone to accept; with it set, the challenge is private to that wallet and they
// get a live "wants to fight you" push over the arena websocket (they can also still find it via
// IncomingChallenges on load/reconnect). wagerWeiStr is what each side will stake in native
// currency (as a wei-string, e.g. "10000000000000000" for 0.01 ETH/ARB), "" or "0" for no wager.
//
// A wagered challenge starts with escrow_confirmed=false and stays invisible to everyone but the
// challenger (see OpenChallenges/IncomingChallenges) until ConfirmEscrow verifies their
// createEscrow() call actually landed on BattleEscrow -- nothing is "open" to accept before the
// stake is real.
func (s *Service) CreateChallenge(ctx context.Context, wallet string, creatureTokenID int64, challengedWallet string, wagerWeiStr string) (*ChallengeSummary, error) {
	if _, err := s.requireOwnedAliveCreature(ctx, wallet, creatureTokenID); err != nil {
		return nil, err
	}
	wagerWei, err := parseWagerWei(wagerWeiStr)
	if err != nil {
		return nil, err
	}
	challengedWallet = strings.TrimSpace(challengedWallet)
	if challengedWallet != "" && strings.EqualFold(challengedWallet, wallet) {
		return nil, errors.New("you can't challenge yourself")
	}

	var openCount int
	if err := s.db.QueryRow(ctx,
		`SELECT COUNT(*) FROM battle_challenges WHERE challenger_wallet = $1 AND status = 'open'`, wallet,
	).Scan(&openCount); err != nil {
		return nil, fmt.Errorf("counting open challenges: %w", err)
	}
	if openCount >= maxOpenChallengesPerWallet {
		return nil, fmt.Errorf("you already have %d open challenges -- cancel one first", maxOpenChallengesPerWallet)
	}

	var challengedCol *string
	if challengedWallet != "" {
		challengedCol = &challengedWallet
	}
	escrowConfirmed := wagerWei.Sign() == 0

	var id int64
	err = s.db.QueryRow(ctx, `
		INSERT INTO battle_challenges (challenger_wallet, challenger_creature_token_id, expires_at, challenged_wallet, wager_wei, escrow_confirmed)
		VALUES ($1, $2, now() + $3, $4, $5, $6)
		RETURNING id`, wallet, creatureTokenID, challengeTTL, challengedCol, wagerWei.String(), escrowConfirmed).Scan(&id)
	if err != nil {
		return nil, fmt.Errorf("creating challenge: %w", err)
	}

	summary, err := s.getChallenge(ctx, id)
	if err != nil {
		return nil, err
	}
	if challengedCol != nil && escrowConfirmed {
		s.notify(challengedWallet, "challenge_received", summary)
	}
	return summary, nil
}

func parseWagerWei(wagerWeiStr string) (*big.Int, error) {
	if wagerWeiStr == "" {
		return big.NewInt(0), nil
	}
	wagerWei, ok := new(big.Int).SetString(wagerWeiStr, 10)
	if !ok || wagerWei.Sign() < 0 {
		return nil, fmt.Errorf("%w: not a valid amount", ErrInvalidWager)
	}
	if wagerWei.Cmp(maxWagerWei) > 0 {
		return nil, fmt.Errorf("%w: must be at most %s wei", ErrInvalidWager, maxWagerWei.String())
	}
	return wagerWei, nil
}

// ConfirmEscrow is called after the challenger's createEscrow() transaction on BattleEscrow
// mines -- it reads the escrow back from the chain itself (never trusts a client-supplied
// amount) and, once it matches, flips the challenge visible on the board/incoming list.
func (s *Service) ConfirmEscrow(ctx context.Context, wallet string, challengeID int64) (*ChallengeSummary, error) {
	var challengerWallet, wagerWeiStr, status string
	var challengedWallet *string
	var escrowConfirmed bool
	err := s.db.QueryRow(ctx,
		`SELECT challenger_wallet, wager_wei, status, challenged_wallet, escrow_confirmed FROM battle_challenges WHERE id = $1`,
		challengeID,
	).Scan(&challengerWallet, &wagerWeiStr, &status, &challengedWallet, &escrowConfirmed)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrChallengeNotFound
		}
		return nil, err
	}
	if !strings.EqualFold(challengerWallet, wallet) {
		return nil, ErrNotChallenger
	}
	if status != "open" {
		return nil, ErrChallengeNotOpen
	}
	if escrowConfirmed {
		return s.getChallenge(ctx, challengeID) // already confirmed -- idempotent
	}

	wagerWei, ok := new(big.Int).SetString(wagerWeiStr, 10)
	if !ok || wagerWei.Sign() == 0 {
		return nil, fmt.Errorf("%w: this challenge has no wager to confirm", ErrEscrowMismatch)
	}

	onChainChallenger, _, onChainWagerWei, onChainStatus, err := s.escrow.GetEscrow(ctx, challengeID)
	if err != nil {
		return nil, fmt.Errorf("reading escrow state: %w", err)
	}
	if onChainStatus != escrowStatusOpen {
		return nil, fmt.Errorf("%w: no confirmed stake found on-chain yet", ErrEscrowNotFunded)
	}
	if !strings.EqualFold(onChainChallenger, wallet) || onChainWagerWei.Cmp(wagerWei) != 0 {
		return nil, fmt.Errorf("%w: on-chain stake doesn't match this challenge", ErrEscrowMismatch)
	}

	if _, err := s.db.Exec(ctx, `UPDATE battle_challenges SET escrow_confirmed = true WHERE id = $1`, challengeID); err != nil {
		return nil, fmt.Errorf("confirming escrow: %w", err)
	}

	summary, err := s.getChallenge(ctx, challengeID)
	if err != nil {
		return nil, err
	}
	if challengedWallet != nil {
		s.notify(*challengedWallet, "challenge_received", summary)
	}
	return summary, nil
}

// CancelChallenge withdraws an open challenge -- only the challenger may do this.
func (s *Service) CancelChallenge(ctx context.Context, wallet string, challengeID int64) error {
	var challenger, status string
	err := s.db.QueryRow(ctx,
		`SELECT challenger_wallet, status FROM battle_challenges WHERE id = $1`, challengeID,
	).Scan(&challenger, &status)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrChallengeNotFound
		}
		return err
	}
	if !strings.EqualFold(challenger, wallet) {
		return ErrNotChallenger
	}
	if status != "open" {
		return ErrChallengeNotOpen
	}
	_, err = s.db.Exec(ctx, `UPDATE battle_challenges SET status = 'cancelled', resolved_at = now() WHERE id = $1`, challengeID)
	return err
}

const challengeColumns = `c.id, c.challenger_wallet, c.challenger_creature_token_id, cr.species, cr.rarity, cr.care_score,
	       c.status, c.challenged_wallet, c.opponent_wallet, c.winner_wallet, c.rounds, c.log, c.reward_feed, c.wager_wei,
	       c.escrow_confirmed, c.created_at, c.expires_at, c.resolved_at`

// OpenChallenges lists every live *public* challenge for the arena board to display -- direct
// (targeted) challenges are private to the wallet they're addressed to and never appear here.
// A wagered challenge whose escrow isn't confirmed yet stays invisible: nothing is actually
// staked until then.
func (s *Service) OpenChallenges(ctx context.Context) ([]ChallengeSummary, error) {
	rows, err := s.db.Query(ctx, `
		SELECT `+challengeColumns+`
		FROM battle_challenges c
		JOIN creatures cr ON cr.token_id = c.challenger_creature_token_id
		WHERE c.status = 'open' AND c.expires_at > now() AND c.challenged_wallet IS NULL AND c.escrow_confirmed
		ORDER BY c.created_at DESC
		LIMIT 50`)
	if err != nil {
		return nil, fmt.Errorf("listing open challenges: %w", err)
	}
	defer rows.Close()
	return scanChallenges(rows)
}

// IncomingChallenges lists live direct challenges addressed to this wallet -- the fallback for
// discovering them on page load/reconnect, since the websocket push only reaches an already-open
// connection. Same escrow-confirmed gate as OpenChallenges.
func (s *Service) IncomingChallenges(ctx context.Context, wallet string) ([]ChallengeSummary, error) {
	rows, err := s.db.Query(ctx, `
		SELECT `+challengeColumns+`
		FROM battle_challenges c
		JOIN creatures cr ON cr.token_id = c.challenger_creature_token_id
		WHERE c.status = 'open' AND c.expires_at > now() AND c.challenged_wallet = $1 AND c.escrow_confirmed
		ORDER BY c.created_at DESC
		LIMIT 20`, wallet)
	if err != nil {
		return nil, fmt.Errorf("listing incoming challenges: %w", err)
	}
	defer rows.Close()
	return scanChallenges(rows)
}

// MyChallenges lists challenges this wallet issued, newest first -- a fallback for noticing a
// challenge got accepted alongside the real-time "challenge_resolved" websocket push.
func (s *Service) MyChallenges(ctx context.Context, wallet string, limit int) ([]ChallengeSummary, error) {
	rows, err := s.db.Query(ctx, `
		SELECT `+challengeColumns+`
		FROM battle_challenges c
		JOIN creatures cr ON cr.token_id = c.challenger_creature_token_id
		WHERE c.challenger_wallet = $1
		ORDER BY c.created_at DESC
		LIMIT $2`, wallet, limit)
	if err != nil {
		return nil, fmt.Errorf("listing my challenges: %w", err)
	}
	defer rows.Close()
	return scanChallenges(rows)
}

func (s *Service) getChallenge(ctx context.Context, id int64) (*ChallengeSummary, error) {
	rows, err := s.db.Query(ctx, `
		SELECT `+challengeColumns+`
		FROM battle_challenges c
		JOIN creatures cr ON cr.token_id = c.challenger_creature_token_id
		WHERE c.id = $1`, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out, err := scanChallenges(rows)
	if err != nil {
		return nil, err
	}
	if len(out) == 0 {
		return nil, ErrChallengeNotFound
	}
	return &out[0], nil
}

func scanChallenges(rows pgx.Rows) ([]ChallengeSummary, error) {
	out := []ChallengeSummary{}
	for rows.Next() {
		var c ChallengeSummary
		var careScore int
		var rewardFeed string
		var logBytes []byte
		if err := rows.Scan(&c.ID, &c.ChallengerWallet, &c.ChallengerCreatureTokenID, &c.ChallengerSpecies, &c.ChallengerRarity,
			&careScore, &c.Status, &c.ChallengedWallet, &c.OpponentWallet, &c.WinnerWallet, &c.Rounds, &logBytes, &rewardFeed, &c.WagerWei,
			&c.EscrowConfirmed, &c.CreatedAt, &c.ExpiresAt, &c.ResolvedAt); err != nil {
			return nil, err
		}
		c.ChallengerLevel = LevelForCareScore(careScore)
		if len(logBytes) > 0 {
			if err := json.Unmarshal(logBytes, &c.Log); err != nil {
				return nil, fmt.Errorf("decoding challenge log: %w", err)
			}
		}
		if c.Status != "open" {
			c.RewardFeed = &rewardFeed
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

// AcceptChallenge resolves a PvP duel: the accepting player's creature vs. the challenger's, both
// using their real care-driven stats. The winner's owner gets $FEED + XP; both sides get a
// `battles` row (so PvP wins count toward the same leaderboard and win_3_battles/play_minigame
// progress as PvE wins). For a wagered challenge, the acceptor must have already called
// acceptEscrow() on BattleEscrow (paying the matching stake) *before* calling this -- it's
// verified against the chain itself, never trusted from the request.
func (s *Service) AcceptChallenge(ctx context.Context, wallet string, challengeID int64, creatureTokenID int64) (*Result, error) {
	var challengerWallet string
	var challengerCreatureID int64
	var status string
	var expiresAt time.Time
	var challengedWallet *string
	var wagerWeiStr string
	err := s.db.QueryRow(ctx,
		`SELECT challenger_wallet, challenger_creature_token_id, status, expires_at, challenged_wallet, wager_wei FROM battle_challenges WHERE id = $1`,
		challengeID,
	).Scan(&challengerWallet, &challengerCreatureID, &status, &expiresAt, &challengedWallet, &wagerWeiStr)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrChallengeNotFound
		}
		return nil, err
	}
	if strings.EqualFold(challengerWallet, wallet) {
		return nil, ErrOwnChallenge
	}
	if challengedWallet != nil && !strings.EqualFold(*challengedWallet, wallet) {
		return nil, ErrNotTargeted
	}
	if status != "open" {
		return nil, ErrChallengeNotOpen
	}
	if time.Now().After(expiresAt) {
		_, _ = s.db.Exec(ctx, `UPDATE battle_challenges SET status = 'expired', resolved_at = now() WHERE id = $1`, challengeID)
		return nil, ErrChallengeExpired
	}

	wagerWei, ok := new(big.Int).SetString(wagerWeiStr, 10)
	if !ok {
		wagerWei = big.NewInt(0)
	}
	if wagerWei.Sign() > 0 {
		onChainChallenger, onChainAcceptor, onChainWagerWei, onChainStatus, err := s.escrow.GetEscrow(ctx, challengeID)
		if err != nil {
			return nil, fmt.Errorf("reading escrow state: %w", err)
		}
		if onChainStatus != escrowStatusAccepted {
			return nil, fmt.Errorf("%w: stake your wager on-chain first (acceptEscrow), then accept", ErrEscrowNotFunded)
		}
		if !strings.EqualFold(onChainChallenger, challengerWallet) || !strings.EqualFold(onChainAcceptor, wallet) || onChainWagerWei.Cmp(wagerWei) != 0 {
			return nil, fmt.Errorf("%w: on-chain stake doesn't match this challenge", ErrEscrowMismatch)
		}
	}

	acceptor, err := s.requireOwnedAliveCreature(ctx, wallet, creatureTokenID)
	if err != nil {
		return nil, err
	}
	challenger, err := s.loadCreature(ctx, challengerCreatureID)
	if err != nil {
		return nil, err
	}
	if challenger.isDead {
		_, _ = s.db.Exec(ctx, `UPDATE battle_challenges SET status = 'cancelled', resolved_at = now() WHERE id = $1`, challengeID)
		return nil, ErrChallengeNotOpen
	}

	// Claim the challenge atomically first (status open -> completed) so two simultaneous accepts
	// can't both resolve the same challenge.
	tag, err := s.db.Exec(ctx, `
		UPDATE battle_challenges SET status = 'completed', opponent_wallet = $2, opponent_creature_token_id = $3
		WHERE id = $1 AND status = 'open'`, challengeID, wallet, creatureTokenID)
	if err != nil {
		return nil, fmt.Errorf("claiming challenge: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return nil, ErrChallengeNotOpen // someone else claimed it first
	}

	rng := rand.New(rand.NewSource(time.Now().UnixNano()))

	aMaxHP, aAtk, aDef, aMods, aAbilityKeys, err := s.statsWithAbilities(ctx, creatureTokenID, int(acceptor.species), int(acceptor.rarity), acceptor.careScore)
	if err != nil {
		return nil, err
	}
	cMaxHP, cAtk, cDef, cMods, cAbilityKeys, err := s.statsWithAbilities(ctx, challengerCreatureID, int(challenger.species), int(challenger.rarity), challenger.careScore)
	if err != nil {
		return nil, err
	}

	acceptorLabel := fmt.Sprintf("%s (%s)", models.SpeciesName(acceptor.species), shortAddress(wallet))
	challengerLabel := fmt.Sprintf("%s (%s)", models.SpeciesName(challenger.species), shortAddress(challengerWallet))

	aHP, cHP, rounds, logLines := simulate(rng, acceptorLabel, aMaxHP, aAtk, aDef, aMods, challengerLabel, cMaxHP, cAtk, cDef, cMods)

	acceptorWon := aHP > cHP
	winnerWallet := wallet
	if !acceptorWon {
		winnerWallet = challengerWallet
	}

	xp := xpForOpponent(int(challenger.rarity))
	if acceptorWon {
		xp = xpForOpponent(int(acceptor.rarity))
	}
	rewardFeed := rewardForOpponent(int(challenger.rarity))
	if acceptorWon {
		rewardFeed = rewardForOpponent(int(acceptor.rarity))
	}

	txHash, err := s.minter.MintReward(ctx, winnerWallet, rewardFeed)
	if err != nil {
		return nil, fmt.Errorf("minting PvP reward: %w", err)
	}
	if err := s.awardXP(ctx, winnerWallet, xp); err != nil {
		return nil, fmt.Errorf("awarding XP: %w", err)
	}
	for _, taskID := range []string{"play_minigame", "win_3_battles"} {
		if err := s.tasks.RecordProgress(ctx, winnerWallet, taskID, 1); err != nil && !errors.Is(err, task.ErrTaskNotFound) {
			return nil, fmt.Errorf("recording PvP task progress: %w", err)
		}
	}

	logJSON, err := json.Marshal(logLines)
	if err != nil {
		return nil, fmt.Errorf("encoding challenge log: %w", err)
	}
	_, err = s.db.Exec(ctx, `
		UPDATE battle_challenges
		SET winner_wallet = $2, rounds = $3, log = $4, reward_feed = $5, resolved_at = now()
		WHERE id = $1`, challengeID, winnerWallet, rounds, logJSON, rewardFeed.String())
	if err != nil {
		return nil, fmt.Errorf("recording challenge result: %w", err)
	}

	// Mirror into `battles` for both participants so PvP results count toward the leaderboard and
	// task progress the same way PvE wins do.
	if err := s.recordBattleRow(ctx, wallet, creatureTokenID, challenger.species, challenger.rarity, acceptorWon, rounds,
		rewardIfWinner(rewardFeed, acceptorWon)); err != nil {
		return nil, err
	}
	if err := s.recordBattleRow(ctx, challengerWallet, challengerCreatureID, acceptor.species, acceptor.rarity, !acceptorWon, rounds,
		rewardIfWinner(rewardFeed, !acceptorWon)); err != nil {
		return nil, err
	}

	// Release the wager pot on-chain now that a winner is durably recorded -- combat and the
	// $FEED reward are already committed above, so a resolve failure here doesn't lose anything:
	// both stakes stay safely locked in BattleEscrow (status Accepted) until resolve() succeeds,
	// whenever that ends up being.
	var escrowResolveTx string
	if wagerWei.Sign() > 0 {
		escrowResolveTx, err = s.escrow.ResolveEscrow(ctx, challengeID, winnerWallet)
		if err != nil {
			return nil, fmt.Errorf("releasing wager pot: %w (your stake is safe in escrow -- try accepting again, or the challenger can retry resolving it)", err)
		}
		if _, err := s.db.Exec(ctx, `UPDATE battle_challenges SET escrow_resolve_tx = $2 WHERE id = $1`, challengeID, escrowResolveTx); err != nil {
			slog.Error("recording escrow resolve tx failed", "challengeId", challengeID, "error", err)
		}
		pot := new(big.Int).Mul(wagerWei, big.NewInt(2))
		rake := new(big.Int).Div(new(big.Int).Mul(pot, big.NewInt(wagerRakeBps)), big.NewInt(10000))
		if rake.Sign() > 0 {
			loserWallet := challengerWallet
			if !acceptorWon {
				loserWallet = wallet
			}
			s.recordRevenue(ctx, "wager_rake", loserWallet, rake)
		}
	}

	result := &Result{
		Won:               acceptorWon,
		PlayerSpecies:     int(acceptor.species),
		PlayerLevel:       LevelForCareScore(acceptor.careScore),
		PlayerHP:          aHP,
		PlayerMaxHP:       aMaxHP,
		PlayerAbilities:   aAbilityKeys,
		OpponentSpecies:   int(challenger.species),
		OpponentRarity:    int(challenger.rarity),
		OpponentLevel:     LevelForCareScore(challenger.careScore),
		OpponentHP:        cHP,
		OpponentMaxHP:     cMaxHP,
		OpponentAbilities: cAbilityKeys,
		Rounds:            rounds,
		Log:               logLines,
		RewardFeed:        rewardIfWinner(rewardFeed, acceptorWon).String(),
		XPAwarded:         xp,
		TxHash:            txHash,
	}
	if wagerWei.Sign() > 0 {
		result.WagerWei = wagerWei.String()
		result.WagerWon = acceptorWon
		result.EscrowResolveTx = escrowResolveTx
	}

	// Mirror the same result to the challenger, HP-swapped to their point of view, and push it over
	// their arena websocket -- this is how they find out their challenge got accepted in real time
	// instead of waiting on the next MyChallenges poll.
	challengerResult := *result
	challengerResult.Won = !acceptorWon
	challengerResult.PlayerSpecies, challengerResult.OpponentSpecies = result.OpponentSpecies, result.PlayerSpecies
	challengerResult.PlayerLevel, challengerResult.OpponentLevel = result.OpponentLevel, result.PlayerLevel
	challengerResult.PlayerHP, challengerResult.OpponentHP = result.OpponentHP, result.PlayerHP
	challengerResult.PlayerMaxHP, challengerResult.OpponentMaxHP = result.OpponentMaxHP, result.PlayerMaxHP
	challengerResult.PlayerAbilities, challengerResult.OpponentAbilities = result.OpponentAbilities, result.PlayerAbilities
	challengerResult.OpponentRarity = int(acceptor.rarity)
	challengerResult.RewardFeed = rewardIfWinner(rewardFeed, !acceptorWon).String()
	if wagerWei.Sign() > 0 {
		challengerResult.WagerWon = !acceptorWon
	}
	s.notify(challengerWallet, "challenge_resolved", map[string]any{
		"challengeId": challengeID,
		"result":      challengerResult,
	})

	return result, nil
}

func rewardIfWinner(reward *big.Int, isWinner bool) *big.Int {
	if isWinner {
		return reward
	}
	return big.NewInt(0)
}

// battleWinCareBonus is how much care_score a win adds -- the same lever feeding uses (see
// gamestate.onCreatureFed's +2/feed), just bigger: "battle it to raise its stats and value" is
// meant to be a real alternative to grinding feeds, not a rounding error next to them.
const battleWinCareBonus = 10

func (s *Service) recordBattleRow(ctx context.Context, wallet string, creatureTokenID int64, oppSpecies, oppRarity int16, won bool, rounds int, reward *big.Int) error {
	_, err := s.db.Exec(ctx, `
		INSERT INTO battles (wallet_address, creature_token_id, opponent_species, opponent_rarity, won, rounds, reward_feed)
		VALUES ($1, $2, $3, $4, $5, $6, $7)`,
		wallet, creatureTokenID, oppSpecies, oppRarity, won, rounds, reward.String())
	if err != nil {
		return fmt.Errorf("recording battle: %w", err)
	}

	if won {
		if _, err := s.db.Exec(ctx, `
			UPDATE creatures SET care_score = care_score + $2, updated_at = now() WHERE token_id = $1`,
			creatureTokenID, battleWinCareBonus); err != nil {
			return fmt.Errorf("applying battle-win stat bonus: %w", err)
		}
	}
	return nil
}

func shortAddress(address string) string {
	if len(address) < 10 {
		return address
	}
	return address[:6] + "..." + address[len(address)-4:]
}
