// Package gamestate implements the indexer that mirrors CreatureNFT and EggNFT on-chain events
// into the `players`, `creatures`, and `eggs` Postgres tables -- the same event-sourcing pattern
// as internal/services/marketplace, just for game state instead of listings. Without this, the
// Farm/Inventory screens would have nothing to read: the contracts are the source of truth, but
// the Flutter app queries Postgres for speed and offline-first caching.
package gamestate

import (
	"context"
	"fmt"
	"log/slog"
	"math/big"
	"math/rand"
	"time"

	"github.com/eggfarm/backend/internal/models"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/jackc/pgx/v5/pgxpool"
)

const cursorKey = "GameState"

// LogFilterer is satisfied by internal/chain.Client.
type LogFilterer interface {
	FilterLogs(ctx context.Context, addresses []common.Address, fromBlock, toBlock uint64) ([]types.Log, error)
	CreatureNFTABI() abi.ABI
	EggNFTABI() abi.ABI
	LatestBlock(ctx context.Context) (uint64, error)
	BlockTime(ctx context.Context, blockNumber uint64) (time.Time, error)
}

// ProgressRecorder is satisfied by internal/services/task.Service. Verified on-chain activity
// is what actually completes a task -- feeding a creature, laying an egg -- not a client telling
// the backend "I did the thing," so the indexer (which only ever sees confirmed events) is the
// one place progress gets recorded.
type ProgressRecorder interface {
	RecordProgressAt(ctx context.Context, wallet, taskID string, delta int, at time.Time) error
}

type Indexer struct {
	db          *pgxpool.Pool
	chain       LogFilterer
	tasks       ProgressRecorder
	deployBlock uint64
	batchSize   uint64

	creatureNFTAddress common.Address
	eggNFTAddress      common.Address

	// Reset each tick: a handful of logs in a batch usually share a small set of block numbers,
	// so caching avoids a redundant HeaderByNumber round trip per log.
	blockTimeCache map[uint64]time.Time
}

func NewIndexer(db *pgxpool.Pool, chain LogFilterer, tasks ProgressRecorder, deployBlock uint64, creatureNFTAddress, eggNFTAddress string) *Indexer {
	return &Indexer{
		db:                 db,
		chain:              chain,
		tasks:              tasks,
		deployBlock:        deployBlock,
		batchSize:          2000,
		creatureNFTAddress: common.HexToAddress(creatureNFTAddress),
		eggNFTAddress:      common.HexToAddress(eggNFTAddress),
	}
}

// recordTaskProgress logs and swallows errors rather than propagating them: a task-tracking
// hiccup (e.g. the row doesn't exist yet) must never block indexing the actual game state, which
// is the source of truth the contracts themselves rely on nothing else to reconstruct.
func (idx *Indexer) recordTaskProgress(ctx context.Context, wallet, taskID string, at time.Time) {
	if idx.tasks == nil {
		return
	}
	if err := idx.tasks.RecordProgressAt(ctx, wallet, taskID, 1, at); err != nil {
		slog.Error("gamestate indexer: recording task progress failed", "wallet", wallet, "taskId", taskID, "error", err)
	}
}

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
		slog.Error("gamestate indexer: reading cursor failed", "error", err)
		return
	}

	latest, err := idx.chain.LatestBlock(ctx)
	if err != nil {
		slog.Error("gamestate indexer: fetching latest block failed", "error", err)
		return
	}
	if from > latest {
		return
	}

	creatureABI := idx.chain.CreatureNFTABI()
	eggABI := idx.chain.EggNFTABI()
	idx.blockTimeCache = make(map[uint64]time.Time)

	for from <= latest {
		to := from + idx.batchSize
		if to > latest {
			to = latest
		}

		logs, err := idx.chain.FilterLogs(ctx, []common.Address{idx.creatureNFTAddress, idx.eggNFTAddress}, from, to)
		if err != nil {
			slog.Error("gamestate indexer: filtering logs failed", "from", from, "to", to, "error", err)
			return
		}

		for _, log := range logs {
			if handleErr := idx.handleLogSafely(ctx, creatureABI, eggABI, log); handleErr != nil {
				slog.Error("gamestate indexer: handling log failed", "txHash", log.TxHash.Hex(), "error", handleErr)
			}
		}

		if err := idx.saveCursor(ctx, to+1); err != nil {
			slog.Error("gamestate indexer: saving cursor failed", "error", err)
			return
		}
		from = to + 1
	}
}

// handleLogSafely recovers from a decode panic on a single malformed/unexpected log (e.g. an ABI
// mismatch after a contract upgrade) so it can't take down the whole indexer goroutine -- and by
// extension the server process, since nothing else in cmd/server recovers panics from background
// goroutines.
func (idx *Indexer) handleLogSafely(ctx context.Context, creatureABI, eggABI abi.ABI, log types.Log) (err error) {
	defer func() {
		if r := recover(); r != nil {
			err = fmt.Errorf("panic handling log: %v", r)
		}
	}()

	switch log.Address {
	case idx.creatureNFTAddress:
		return idx.handleCreatureLog(ctx, creatureABI, log)
	case idx.eggNFTAddress:
		return idx.handleEggLog(ctx, eggABI, log)
	}
	return nil
}

func (idx *Indexer) handleCreatureLog(ctx context.Context, contractABI abi.ABI, log types.Log) error {
	if len(log.Topics) == 0 {
		return nil
	}
	event, err := contractABI.EventByID(log.Topics[0])
	if err != nil {
		return nil // Transfer and other events not in our decode map are skipped below if unnamed
	}

	switch event.Name {
	case "CreatureMinted":
		return idx.onCreatureMinted(ctx, contractABI, log)
	case "CreatureFed":
		return idx.onCreatureFed(ctx, contractABI, log)
	case "CreatureStarved":
		return idx.onCreatureStarved(ctx, log)
	case "EggLaidBySpontaneous":
		return idx.onCreatureLaidEgg(ctx, contractABI, log)
	case "CreaturesBred":
		return idx.onCreaturesBred(ctx, contractABI, log)
	case "Transfer":
		return idx.onCreatureTransfer(ctx, contractABI, log)
	default:
		return nil
	}
}

func (idx *Indexer) handleEggLog(ctx context.Context, contractABI abi.ABI, log types.Log) error {
	if len(log.Topics) == 0 {
		return nil
	}
	event, err := contractABI.EventByID(log.Topics[0])
	if err != nil {
		return nil
	}

	switch event.Name {
	case "EggLaid":
		return idx.onEggLaid(ctx, contractABI, log)
	case "EggHatched":
		return idx.onEggHatched(ctx, contractABI, log)
	case "EggDiscarded":
		return idx.onEggDiscarded(ctx, log)
	case "EggTended":
		return idx.onEggTended(ctx, contractABI, log)
	case "EggSpoiled":
		return idx.onEggSpoiled(ctx, log)
	case "EggHatchSpedUp":
		return idx.onEggHatchSpedUp(ctx, contractABI, log)
	case "Transfer":
		return idx.onEggTransfer(ctx, contractABI, log)
	default:
		return nil
	}
}

// --- CreatureNFT handlers ---

func (idx *Indexer) onCreatureMinted(ctx context.Context, contractABI abi.ABI, log types.Log) error {
	data, err := decode(contractABI, "CreatureMinted", log)
	if err != nil {
		return err
	}
	tokenID := data["tokenId"].(*big.Int).Int64()
	owner := data["owner"].(common.Address).Hex()
	species := data["species"].(uint8)
	rarity := data["rarity"].(uint8)

	if err := idx.ensurePlayer(ctx, owner); err != nil {
		return err
	}

	// Named here so a direct purchaseCreature() mint (no egg involved) still gets one; the far more
	// common hatch path immediately overwrites it with the egg's own nickname in onEggHatched,
	// which fires right after this within the same hatchEgg() transaction.
	_, err = idx.db.Exec(ctx, `
		INSERT INTO creatures (token_id, owner_address, species, rarity, breed_count, happiness, birth_time, last_fed_at, nickname)
		VALUES ($1, $2, $3, $4, 0, 50, now(), now(), $5)
		ON CONFLICT (token_id) DO UPDATE SET owner_address = $2, updated_at = now()`,
		tokenID, owner, species, rarity, models.GenerateNickname(tokenID))
	if err != nil {
		return err
	}

	// Species dex entry: permanent once earned, regardless of what later happens to this
	// specific creature (sold, dies, bred away) -- see migrations/0004_species_dex.sql.
	_, err = idx.db.Exec(ctx, `
		INSERT INTO species_dex (wallet_address, species, first_token_id)
		VALUES ($1, $2, $3)
		ON CONFLICT (wallet_address, species) DO NOTHING`,
		owner, species, tokenID)
	return err
}

func (idx *Indexer) onCreatureFed(ctx context.Context, contractABI abi.ABI, log types.Log) error {
	data, err := decode(contractABI, "CreatureFed", log)
	if err != nil {
		return err
	}
	tokenID := data["tokenId"].(*big.Int).Int64()
	happiness := data["happiness"].(uint8)

	// care_score is the creature-leveling counter: +2 per real feed (see battle.CarePerLevel),
	// nothing self-reported -- it only ever moves in response to a confirmed CreatureFed event.
	var owner string
	err = idx.db.QueryRow(ctx, `
		UPDATE creatures SET happiness = $2, last_fed_at = now(), hunger_zero_since = NULL, neglect_penalized = false,
		                      care_score = care_score + 2, updated_at = now()
		WHERE token_id = $1
		RETURNING owner_address`, tokenID, happiness).Scan(&owner)
	if err != nil {
		return err
	}

	fedAt, err := idx.blockTime(ctx, log.BlockNumber)
	if err != nil {
		return err
	}
	idx.recordTaskProgress(ctx, owner, "feed_3_times", fedAt)
	return nil
}

func (idx *Indexer) onCreatureStarved(ctx context.Context, log types.Log) error {
	tokenID := new(big.Int).SetBytes(log.Topics[1].Bytes()).Int64()
	_, err := idx.db.Exec(ctx, `UPDATE creatures SET is_dead = true, updated_at = now() WHERE token_id = $1`, tokenID)
	return err
}

func (idx *Indexer) onCreatureLaidEgg(ctx context.Context, contractABI abi.ABI, log types.Log) error {
	data, err := decode(contractABI, "EggLaidBySpontaneous", log)
	if err != nil {
		return err
	}
	creatureID := data["creatureId"].(*big.Int).Int64()
	_, err = idx.db.Exec(ctx, `UPDATE creatures SET last_egg_at = now(), updated_at = now() WHERE token_id = $1`, creatureID)
	return err
}

func (idx *Indexer) onCreaturesBred(ctx context.Context, contractABI abi.ABI, log types.Log) error {
	data, err := decode(contractABI, "CreaturesBred", log)
	if err != nil {
		return err
	}
	parent1 := data["parent1"].(*big.Int).Int64()
	parent2 := data["parent2"].(*big.Int).Int64()
	eggTokenID := data["eggTokenId"].(*big.Int).Int64()

	// The egg row already exists (EggLaid fires before CreaturesBred inside breedCreatures()) but
	// EggLaid's own event doesn't carry parent lineage (kept out for gas) -- backfill it here from
	// the one event that does, so onEggHatched has real lineage to roll inherited abilities from.
	if _, err := idx.db.Exec(ctx, `UPDATE eggs SET parent1 = $2, parent2 = $3 WHERE token_id = $1`, eggTokenID, parent1, parent2); err != nil {
		return fmt.Errorf("backfilling egg lineage: %w", err)
	}

	if err := idx.renameIfMutant(ctx, eggTokenID, parent1, parent2); err != nil {
		return fmt.Errorf("checking for breeding mutation: %w", err)
	}

	var owner string
	err = idx.db.QueryRow(ctx, `
		UPDATE creatures SET breed_count = breed_count + 1, updated_at = now()
		WHERE token_id IN ($1, $2)
		RETURNING owner_address`, parent1, parent2).Scan(&owner)
	if err != nil {
		return err
	}

	bredAt, err := idx.blockTime(ctx, log.BlockNumber)
	if err != nil {
		return err
	}
	idx.recordTaskProgress(ctx, owner, "breed_1_creature", bredAt)
	return nil
}

// renameIfMutant overwrites a bred egg's default nickname with a mutant-flavored one when its
// species matches neither parent's -- CreatureNFT.sol's _rollOffspringSpecies already calls this
// exact outcome a "mutation" (cross-species pairs roll it 60% of the time vs 20% same-species), so
// the naming just makes that mechanic visible rather than inventing a new one.
func (idx *Indexer) renameIfMutant(ctx context.Context, eggTokenID, parent1, parent2 int64) error {
	var eggSpecies, p1Species, p2Species int16
	if err := idx.db.QueryRow(ctx, `SELECT species FROM eggs WHERE token_id = $1`, eggTokenID).Scan(&eggSpecies); err != nil {
		return err
	}
	if err := idx.db.QueryRow(ctx, `SELECT species FROM creatures WHERE token_id = $1`, parent1).Scan(&p1Species); err != nil {
		return err
	}
	if err := idx.db.QueryRow(ctx, `SELECT species FROM creatures WHERE token_id = $1`, parent2).Scan(&p2Species); err != nil {
		return err
	}
	if eggSpecies == p1Species || eggSpecies == p2Species {
		return nil // inherited a parent's species -- not a mutation, keep the default nickname
	}
	_, err := idx.db.Exec(ctx, `UPDATE eggs SET nickname = $2 WHERE token_id = $1`, eggTokenID, models.GenerateMutantNickname(eggTokenID))
	return err
}

func (idx *Indexer) onCreatureTransfer(ctx context.Context, contractABI abi.ABI, log types.Log) error {
	from, to, tokenID, err := decodeTransfer(contractABI, log)
	if err != nil {
		return err
	}
	if from == (common.Address{}) {
		return nil // mint: CreatureMinted already created the row with the right owner
	}
	if err := idx.ensurePlayer(ctx, to.Hex()); err != nil {
		return err
	}
	_, err = idx.db.Exec(ctx, `UPDATE creatures SET owner_address = $2, updated_at = now() WHERE token_id = $1`, tokenID, to.Hex())
	return err
}

// --- EggNFT handlers ---

// hatchDuration mirrors CreatureNFT.sol's _hatchDuration: 24h (common) up to 72h (legendary).
func hatchDuration(rarity uint8) time.Duration {
	return 24*time.Hour + time.Duration(rarity-1)*12*time.Hour
}

func (idx *Indexer) onEggLaid(ctx context.Context, contractABI abi.ABI, log types.Log) error {
	data, err := decode(contractABI, "EggLaid", log)
	if err != nil {
		return err
	}
	tokenID := data["tokenId"].(*big.Int).Int64()
	owner := data["owner"].(common.Address).Hex()
	rarity := data["rarity"].(uint8)
	species := data["species"].(uint8)
	isRotten := data["isRotten"].(bool)

	if err := idx.ensurePlayer(ctx, owner); err != nil {
		return err
	}

	laidAt, err := idx.blockTime(ctx, log.BlockNumber)
	if err != nil {
		return err
	}
	// Parent IDs aren't in the event (kept small for gas); a direct getEggInfo() read is the
	// fallback for callers that need them, but the Farm/Inventory screens only need the timer.
	hatchTime := laidAt.Add(hatchDuration(rarity))
	// Named the moment it's laid -- onCreaturesBred overwrites this with a mutant-flavored name
	// if this egg turns out to be a cross-species breeding mutation.
	nickname := models.GenerateNickname(tokenID)

	_, err = idx.db.Exec(ctx, `
		INSERT INTO eggs (token_id, owner_address, rarity, species, hatch_time, is_rotten, is_hatched, laid_at, care_level, last_cared_at, nickname)
		VALUES ($1, $2, $3, $4, $5, $6, false, $7, 100, $7, $8)
		ON CONFLICT (token_id) DO UPDATE SET owner_address = $2`,
		tokenID, owner, rarity, species, hatchTime, isRotten, laidAt, nickname)
	if err != nil {
		return err
	}

	idx.recordTaskProgress(ctx, owner, "collect_1_egg", laidAt)
	return nil
}

func (idx *Indexer) onEggTended(ctx context.Context, contractABI abi.ABI, log types.Log) error {
	data, err := decode(contractABI, "EggTended", log)
	if err != nil {
		return err
	}
	tokenID := data["tokenId"].(*big.Int).Int64()
	careLevel := data["careLevel"].(uint8)

	tendedAt, err := idx.blockTime(ctx, log.BlockNumber)
	if err != nil {
		return err
	}

	var owner string
	err = idx.db.QueryRow(ctx, `
		UPDATE eggs SET care_level = $2, last_cared_at = $3, care_zero_since = NULL
		WHERE token_id = $1
		RETURNING owner_address`, tokenID, careLevel, tendedAt).Scan(&owner)
	if err != nil {
		return err
	}
	idx.recordTaskProgress(ctx, owner, "tend_1_egg", tendedAt)
	return nil
}

func (idx *Indexer) onEggSpoiled(ctx context.Context, log types.Log) error {
	tokenID := new(big.Int).SetBytes(log.Topics[1].Bytes()).Int64()
	_, err := idx.db.Exec(ctx, `UPDATE eggs SET is_rotten = true, care_level = 0 WHERE token_id = $1`, tokenID)
	return err
}

// onEggHatchSpedUp syncs a paid speedUpHatch() call's new (earlier) hatch_time into the cache --
// unlike onEggLaid, this one trusts the event's own timestamp rather than recomputing from
// hatchDuration(rarity), since the whole point of the call is to deviate from that formula.
func (idx *Indexer) onEggHatchSpedUp(ctx context.Context, contractABI abi.ABI, log types.Log) error {
	data, err := decode(contractABI, "EggHatchSpedUp", log)
	if err != nil {
		return err
	}
	tokenID := data["tokenId"].(*big.Int).Int64()
	newHatchTime := time.Unix(int64(data["newHatchTime"].(uint64)), 0)

	_, err = idx.db.Exec(ctx, `UPDATE eggs SET hatch_time = $2 WHERE token_id = $1`, tokenID, newHatchTime)
	return err
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

func (idx *Indexer) onEggHatched(ctx context.Context, contractABI abi.ABI, log types.Log) error {
	data, err := decode(contractABI, "EggHatched", log)
	if err != nil {
		return err
	}
	eggTokenID := data["tokenId"].(*big.Int).Int64()
	creatureID := data["creatureId"].(*big.Int).Int64()

	var parent1, parent2 int64
	var nickname *string
	err = idx.db.QueryRow(ctx, `
		UPDATE eggs SET is_hatched = true WHERE token_id = $1
		RETURNING COALESCE(parent1, 0), COALESCE(parent2, 0), nickname`, eggTokenID).Scan(&parent1, &parent2, &nickname)
	if err != nil {
		return err
	}

	// CreatureMinted (which inserts the `creatures` row) fires before EggHatched within
	// hatchEgg() -- mintFromEgg() is called, then the event -- so the row is guaranteed to exist
	// here already. Carry the egg's name over: same individual, same name, through its whole life.
	if _, err := idx.db.Exec(ctx, `UPDATE creatures SET nickname = $2 WHERE token_id = $1`, creatureID, nickname); err != nil {
		return fmt.Errorf("carrying nickname over to hatched creature: %w", err)
	}

	return idx.assignAbilities(ctx, creatureID, parent1, parent2)
}

// assignAbilities rolls a new creature's starting ability set once, right after it's minted.
// parent1/parent2 being non-zero means this creature was bred: it inherits from its parents'
// actual ability pools instead of rolling fresh, which is what makes bloodlines matter and (via
// the mutation roll) is how breeding can hand an offspring an ability neither parent had.
func (idx *Indexer) assignAbilities(ctx context.Context, creatureID, parent1, parent2 int64) error {
	var rarity int
	if err := idx.db.QueryRow(ctx, `SELECT rarity FROM creatures WHERE token_id = $1`, creatureID).Scan(&rarity); err != nil {
		return fmt.Errorf("reading new creature's rarity for ability roll: %w", err)
	}

	rng := rand.New(rand.NewSource(time.Now().UnixNano() + creatureID))
	const maxAbilities = 4

	// key -> source ('inherited'/'mutated'/'genesis'), built up as abilities are rolled.
	chosen := map[string]string{}

	if parent1 > 0 && parent2 > 0 {
		parentAbilities, err := idx.abilityKeysFor(ctx, parent1, parent2)
		if err != nil {
			return err
		}
		for _, key := range parentAbilities {
			if len(chosen) >= maxAbilities {
				break
			}
			if rng.Float64() < 0.5 { // each of a parent's abilities has a 50% shot at passing on
				chosen[key] = "inherited"
			}
		}
		// A bred creature always has a chance at a wholly new ability, mutation-style, drawn from
		// the full catalog (not rarity-gated the way a genesis roll is) -- this is how a low-rarity
		// bloodline can eventually carry a high-tier ability neither parent had.
		if len(chosen) < maxAbilities && rng.Float64() < 0.2 {
			if mutated := randomUnusedAbility(rng, models.AbilityCatalog, chosen); mutated != "" {
				chosen[mutated] = "mutated"
			}
		}
	}

	if len(chosen) == 0 {
		// Either a genesis (non-bred) creature, or a bred one that rolled no inherited/mutated
		// ability -- either way it still gets a real starting kit, rarity-gated.
		pool := models.AbilitiesForRarity(rarity)
		count := 1 + rarity/2 // rarity 1-2 -> 1, 3-4 -> 2, 5 -> 3
		if count > maxAbilities {
			count = maxAbilities
		}
		for i := 0; i < count && len(pool) > 0; i++ {
			pick := pool[rng.Intn(len(pool))]
			chosen[pick.Key] = "genesis"
		}
	}

	for key, src := range chosen {
		if _, err := idx.db.Exec(ctx, `
			INSERT INTO creature_abilities (creature_token_id, ability_key, source)
			VALUES ($1, $2, $3)
			ON CONFLICT DO NOTHING`, creatureID, key, src); err != nil {
			return fmt.Errorf("recording ability %s for creature %d: %w", key, creatureID, err)
		}
	}
	return nil
}

// abilityKeysFor returns the de-duplicated union of both parents' current ability keys.
func (idx *Indexer) abilityKeysFor(ctx context.Context, parent1, parent2 int64) ([]string, error) {
	rows, err := idx.db.Query(ctx, `
		SELECT DISTINCT ability_key FROM creature_abilities WHERE creature_token_id IN ($1, $2)`, parent1, parent2)
	if err != nil {
		return nil, fmt.Errorf("reading parent abilities: %w", err)
	}
	defer rows.Close()

	var keys []string
	for rows.Next() {
		var key string
		if err := rows.Scan(&key); err != nil {
			return nil, err
		}
		keys = append(keys, key)
	}
	return keys, rows.Err()
}

// randomUnusedAbility picks a random catalog ability not already a key in `exclude`; returns ""
// if the creature already somehow has every ability in the catalog.
func randomUnusedAbility(rng *rand.Rand, catalog map[string]models.Ability, exclude map[string]string) string {
	candidates := make([]string, 0, len(catalog))
	for key := range catalog {
		if _, has := exclude[key]; !has {
			candidates = append(candidates, key)
		}
	}
	if len(candidates) == 0 {
		return ""
	}
	return candidates[rng.Intn(len(candidates))]
}

func (idx *Indexer) onEggDiscarded(ctx context.Context, log types.Log) error {
	tokenID := new(big.Int).SetBytes(log.Topics[1].Bytes()).Int64()
	_, err := idx.db.Exec(ctx, `UPDATE eggs SET is_hatched = true WHERE token_id = $1`, tokenID)
	return err
}

func (idx *Indexer) onEggTransfer(ctx context.Context, contractABI abi.ABI, log types.Log) error {
	from, to, tokenID, err := decodeTransfer(contractABI, log)
	if err != nil {
		return err
	}
	if from == (common.Address{}) {
		return nil // mint: EggLaid already created the row
	}
	if err := idx.ensurePlayer(ctx, to.Hex()); err != nil {
		return err
	}
	_, err = idx.db.Exec(ctx, `UPDATE eggs SET owner_address = $2 WHERE token_id = $1`, tokenID, to.Hex())
	return err
}

// --- shared helpers ---

func (idx *Indexer) ensurePlayer(ctx context.Context, wallet string) error {
	_, err := idx.db.Exec(ctx, `
		INSERT INTO players (wallet_address) VALUES ($1)
		ON CONFLICT (wallet_address) DO NOTHING`, wallet)
	return err
}

func decode(contractABI abi.ABI, eventName string, log types.Log) (map[string]interface{}, error) {
	data := map[string]interface{}{}
	if err := contractABI.UnpackIntoMap(data, eventName, log.Data); err != nil {
		return nil, fmt.Errorf("unpacking %s data: %w", eventName, err)
	}
	if err := abi.ParseTopicsIntoMap(data, indexedArgs(contractABI, eventName), log.Topics[1:]); err != nil {
		return nil, fmt.Errorf("parsing %s topics: %w", eventName, err)
	}
	return data, nil
}

// decodeTransfer handles the standard ERC-721 Transfer(address,address,uint256) event, whose
// three parameters are all indexed (so all three live in topics, none in data).
func decodeTransfer(contractABI abi.ABI, log types.Log) (from, to common.Address, tokenID int64, err error) {
	data := map[string]interface{}{}
	if err = abi.ParseTopicsIntoMap(data, indexedArgs(contractABI, "Transfer"), log.Topics[1:]); err != nil {
		return common.Address{}, common.Address{}, 0, fmt.Errorf("parsing Transfer topics: %w", err)
	}
	from = data["from"].(common.Address)
	to = data["to"].(common.Address)
	tokenID = data["tokenId"].(*big.Int).Int64()
	return from, to, tokenID, nil
}

func indexedArgs(contractABI abi.ABI, eventName string) abi.Arguments {
	var args abi.Arguments
	for _, input := range contractABI.Events[eventName].Inputs {
		if input.Indexed {
			args = append(args, input)
		}
	}
	return args
}

func (idx *Indexer) cursor(ctx context.Context) (uint64, error) {
	var last int64
	err := idx.db.QueryRow(ctx, `SELECT last_block FROM indexer_cursor WHERE contract_name = $1`, cursorKey).Scan(&last)
	if err != nil {
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
