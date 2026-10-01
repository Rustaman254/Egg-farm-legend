// Package api implements the REST API surface consumed by the Flutter app: farm state,
// task board, marketplace browsing, and egg-outcome previews. See openapi.yaml in the backend
// root for the full contract.
package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"math/big"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/eggfarm/backend/internal/models"
	"github.com/eggfarm/backend/internal/realtime"
	"github.com/eggfarm/backend/internal/services/auth"
	"github.com/eggfarm/backend/internal/services/battle"
	"github.com/eggfarm/backend/internal/services/rng"
	"github.com/eggfarm/backend/internal/services/shop"
	"github.com/eggfarm/backend/internal/services/task"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ChainReader is satisfied by internal/chain.Client.
type ChainReader interface {
	GetFeedBalance(ctx context.Context, wallet string) (*big.Int, error)
	NativeBalance(ctx context.Context, wallet string) (*big.Int, error)
}

type Server struct {
	db     *pgxpool.Pool
	task   *task.Service
	battle *battle.Service
	chain  ChainReader
	hub    *realtime.Hub
	shop   *shop.Service
	auth   *auth.Service
}

func NewRouter(db *pgxpool.Pool, taskSvc *task.Service, battleSvc *battle.Service, chainClient ChainReader, hub *realtime.Hub, shopSvc *shop.Service, authSvc *auth.Service) http.Handler {
	s := &Server{db: db, task: taskSvc, battle: battleSvc, chain: chainClient, hub: hub, shop: shopSvc, auth: authSvc}

	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	// Chrome's Private Network Access policy blocks a public-origin page (e.g. an ngrok tunnel
	// serving the webapp) from silently fetching a loopback/private address (this API on
	// localhost) unless the preflight response explicitly opts in. go-chi/cors has no built-in
	// support for this header, so it's set directly, ahead of cors.Handler in the chain so it's
	// already on the response by the time cors.Handler writes/short-circuits the preflight.
	r.Use(func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Header.Get("Access-Control-Request-Private-Network") == "true" {
				w.Header().Set("Access-Control-Allow-Private-Network", "true")
			}
			next.ServeHTTP(w, r)
		})
	})
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins: []string{"*"},
		AllowedMethods: []string{"GET", "POST", "OPTIONS"},
		AllowedHeaders: []string{"Content-Type", "Authorization"},
	}))

	r.Get("/healthz", s.handleHealth)

	r.Route("/api/auth", func(r chi.Router) {
		r.Post("/register", s.handleRegister)
		r.Post("/login", s.handleLogin)
	})

	r.Route("/api/players/{wallet}", func(r chi.Router) {
		r.Get("/farm", s.handleGetFarm)
		r.Post("/login", s.handleDailyLogin)
		r.Get("/dex", s.handleGetDex)
		r.Get("/activity", s.handleActivity)
		r.Post("/battles", s.handleFightBattle)
		r.Get("/battles", s.handleListBattles)
		r.Post("/challenges", s.handleCreateChallenge)
		r.Get("/challenges", s.handleMyChallenges)
		r.Get("/challenges/incoming", s.handleIncomingChallenges)
		r.Post("/challenges/{challengeId}/confirm-escrow", s.handleConfirmEscrow)
		r.Post("/challenges/{challengeId}/accept", s.handleAcceptChallenge)
		r.Post("/challenges/{challengeId}/cancel", s.handleCancelChallenge)
		r.Post("/arena/heartbeat", s.handleArenaHeartbeat)
		r.Get("/ws", s.handleArenaWebSocket)
		r.Post("/creatures/{tokenId}/nickname", s.handleSetCreatureNickname)
		r.Post("/eggs/{tokenId}/nickname", s.handleSetEggNickname)
	})

	r.Route("/api/arena", func(r chi.Router) {
		r.Get("/online", s.handleArenaOnline)
		r.Get("/challenges", s.handleOpenChallenges)
	})

	r.Route("/api/tasks", func(r chi.Router) {
		r.Get("/{wallet}", s.handleListTasks)
		r.Post("/{wallet}/{taskId}/claim", s.handleClaimTask)
		r.Post("/create", s.handleCreateTask)
		r.Post("/{taskId}/fund", s.handleFundTask)
	})

	r.Route("/api/eggs", func(r chi.Router) {
		r.Get("/preview", s.handleEggPreview)
	})

	r.Route("/api/marketplace", func(r chi.Router) {
		r.Get("/listings", s.handleListListings)
	})

	r.Route("/api/feed-shop", func(r chi.Router) {
		r.Get("/packages", s.handleFeedShopPackages)
		r.Post("/purchase", s.handleFeedShopPurchase)
	})

	r.Get("/api/leaderboard/top-earners", s.handleLeaderboard)
	r.Get("/api/leaderboard/top-battlers", s.handleBattleLeaderboard)

	r.Get("/api/abilities", s.handleAbilityCatalog)

	return r
}

// handleRegister creates a mobile-app account for a wallet the app already generated on-device.
// walletBackup is the password-encrypted keystore JSON -- opaque here, stored only so Login can
// hand it back for the app to decrypt client-side; the backend never sees a usable private key.
func (s *Server) handleRegister(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Username      string `json:"username"`
		Email         string `json:"email"`
		Password      string `json:"password"`
		WalletAddress string `json:"walletAddress"`
		WalletBackup  string `json:"walletBackup"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, errors.New("invalid request body"))
		return
	}
	account, err := s.auth.Register(r.Context(), body.Username, body.Email, body.Password, body.WalletAddress, body.WalletBackup)
	if err != nil {
		writeAuthError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, account)
}

// handleLogin verifies email+password and returns the wallet address + encrypted keystore for
// the app to decrypt locally with the same password -- recovering the same signing key on a new
// device without the backend ever holding it in a usable form.
func (s *Server) handleLogin(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, errors.New("invalid request body"))
		return
	}
	walletAddress, walletBackup, username, err := s.auth.Login(r.Context(), body.Email, body.Password)
	if err != nil {
		writeAuthError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{
		"walletAddress": walletAddress,
		"walletBackup":  walletBackup,
		"username":      username,
	})
}

func writeAuthError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, auth.ErrInvalidCredentials):
		writeError(w, http.StatusUnauthorized, err)
	case errors.Is(err, auth.ErrUsernameTaken), errors.Is(err, auth.ErrEmailTaken), errors.Is(err, auth.ErrWalletTaken):
		writeError(w, http.StatusConflict, err)
	case errors.Is(err, auth.ErrInvalidUsername), errors.Is(err, auth.ErrInvalidEmail), errors.Is(err, auth.ErrPasswordTooShort):
		writeError(w, http.StatusBadRequest, err)
	default:
		writeError(w, http.StatusInternalServerError, err)
	}
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// handleGetFarm returns everything the Farm screen needs in one call: live creatures (with
// derived hunger), unhatched eggs, and the player's $FEED balance.
func (s *Server) handleGetFarm(w http.ResponseWriter, r *http.Request) {
	wallet := chi.URLParam(r, "wallet")
	ctx := r.Context()

	creatures, err := s.fetchCreatures(ctx, wallet)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	eggs, err := s.fetchEggs(ctx, wallet)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}

	// Read live from chain rather than a cached column: $FEED balance changes on every
	// feed/breed/task-claim, and there's no reliable way to keep a cache fresh without an
	// FeedToken Transfer-event indexer, which is more moving parts than a single extra RPC call.
	feedBalance := "0"
	nativeBalance := "0"
	if s.chain != nil {
		balance, err := s.chain.GetFeedBalance(ctx, wallet)
		if err != nil {
			slog.Error("reading feed balance failed", "wallet", wallet, "error", err)
		} else {
			feedBalance = balance.String()
		}
		native, err := s.chain.NativeBalance(ctx, wallet)
		if err != nil {
			slog.Error("reading native balance failed", "wallet", wallet, "error", err)
		} else {
			nativeBalance = native.String()
		}
	}

	var xp int
	if err := s.db.QueryRow(ctx, `SELECT xp FROM players WHERE wallet_address = $1`, wallet).Scan(&xp); err != nil && !errors.Is(err, pgx.ErrNoRows) {
		slog.Error("reading player xp failed", "wallet", wallet, "error", err)
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"creatures":        creatures,
		"eggs":             eggs,
		"feedBalance":      feedBalance,
		"nativeBalanceWei": nativeBalance,
		"xp":               xp,
		"farmerLevel":      farmerLevelForXP(xp),
	})
}

// farmerLevelForXP mirrors the webapp's src/config/farmerLevel.ts LevelForXP -- same curve
// pragmatically re-derived here since the farm endpoint is the one place the level is computed
// server-side (everywhere else just reads the raw xp and computes the same formula client-side).
func farmerLevelForXP(xp int) int {
	level := 1
	for xp >= xpForNextFarmerLevel(level) {
		xp -= xpForNextFarmerLevel(level)
		level++
	}
	return level
}

// xpForNextFarmerLevel: level N->N+1 costs 100*N XP -- a plain linear ramp so the grind is
// predictable (level 2 at 100 XP, level 10 at 4,500 cumulative, level 20 at 19,000 cumulative).
func xpForNextFarmerLevel(level int) int {
	return 100 * level
}

func (s *Server) fetchCreatures(ctx context.Context, wallet string) ([]models.Creature, error) {
	rows, err := s.db.Query(ctx, `
		SELECT token_id, owner_address, species, rarity, breed_count, happiness, care_score,
		       birth_time, last_fed_at, last_egg_at, is_dead, hunger_zero_since, nickname,
		       GREATEST(0, 100 - (FLOOR(EXTRACT(EPOCH FROM (now() - last_fed_at)) / 3600) * 10))::int AS hunger
		FROM creatures
		WHERE owner_address = $1 AND NOT is_dead
		ORDER BY token_id`, wallet)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.Creature
	for rows.Next() {
		var c models.Creature
		if err := rows.Scan(&c.TokenID, &c.OwnerAddress, &c.Species, &c.Rarity, &c.BreedCount, &c.Happiness, &c.CareScore,
			&c.BirthTime, &c.LastFedAt, &c.LastEggAt, &c.IsDead, &c.HungerZeroSince, &c.Nickname, &c.Hunger); err != nil {
			return nil, err
		}
		if c.Hunger > 100 {
			c.Hunger = 100
		}
		c.MaturesAt = c.BirthTime.Add(models.MaturationDuration(c.Rarity))
		c.IsMature = !time.Now().Before(c.MaturesAt)
		out = append(out, c)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if err := s.attachAbilities(ctx, out); err != nil {
		return nil, err
	}
	return out, nil
}

// attachAbilities fills in each creature's Abilities field with one query instead of N -- called
// after the caller's main creature query, on whatever slice it built.
func (s *Server) attachAbilities(ctx context.Context, creatures []models.Creature) error {
	if len(creatures) == 0 {
		return nil
	}
	ids := make([]int64, len(creatures))
	byID := make(map[int64]*models.Creature, len(creatures))
	for i := range creatures {
		ids[i] = creatures[i].TokenID
		byID[creatures[i].TokenID] = &creatures[i]
	}
	rows, err := s.db.Query(ctx, `
		SELECT creature_token_id, ability_key FROM creature_abilities
		WHERE creature_token_id = ANY($1) ORDER BY acquired_at`, ids)
	if err != nil {
		return fmt.Errorf("attaching abilities: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var tokenID int64
		var key string
		if err := rows.Scan(&tokenID, &key); err != nil {
			return err
		}
		if c, ok := byID[tokenID]; ok {
			c.Abilities = append(c.Abilities, key)
		}
	}
	return rows.Err()
}

// minCareToHatch mirrors EggNFT.sol's MIN_CARE_TO_HATCH constant -- a neglected egg can't hatch
// even once its timer is up. Kept in sync manually since Postgres has no way to read a deployed
// contract's constants; if that constant ever changes, this must change with it.
const minCareToHatch = 30

func (s *Server) fetchEggs(ctx context.Context, wallet string) ([]models.Egg, error) {
	rows, err := s.db.Query(ctx, `
		SELECT token_id, owner_address, rarity, species, hatch_time, parent1, parent2,
		       is_rotten, is_hatched, laid_at, care_level, last_cared_at, nickname,
		       (NOT is_rotten AND hatch_time <= now() AND care_level >= $2) AS is_hatchable
		FROM eggs
		WHERE owner_address = $1 AND NOT is_hatched
		ORDER BY token_id`, wallet, minCareToHatch)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.Egg
	for rows.Next() {
		var e models.Egg
		if err := rows.Scan(&e.TokenID, &e.OwnerAddress, &e.Rarity, &e.Species, &e.HatchTime, &e.Parent1, &e.Parent2,
			&e.IsRotten, &e.IsHatched, &e.LaidAt, &e.CareLevel, &e.LastCaredAt, &e.Nickname, &e.IsHatchable); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

// maxNicknameLen keeps rename input reasonable for card/listing layouts across both apps.
const maxNicknameLen = 24

// parseNicknameBody decodes and validates a {"nickname": "..."} body -- trimmed, non-empty, and
// under maxNicknameLen. Shared by both the creature and egg rename handlers.
func parseNicknameBody(r *http.Request) (string, error) {
	var body struct {
		Nickname string `json:"nickname"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		return "", errors.New("invalid request body")
	}
	nickname := strings.TrimSpace(body.Nickname)
	if nickname == "" {
		return "", errors.New("nickname cannot be empty")
	}
	if len(nickname) > maxNicknameLen {
		return "", fmt.Errorf("nickname must be %d characters or fewer", maxNicknameLen)
	}
	return nickname, nil
}

// handleSetCreatureNickname lets an owner rename their own creature -- the species (Chicken,
// Phoenix, ...) stays the type; this is what makes an individual unique, e.g. "Chicken (Prisma)".
func (s *Server) handleSetCreatureNickname(w http.ResponseWriter, r *http.Request) {
	wallet := chi.URLParam(r, "wallet")
	tokenID, err := strconv.ParseInt(chi.URLParam(r, "tokenId"), 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, errors.New("invalid tokenId"))
		return
	}
	nickname, err := parseNicknameBody(r)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	ct, err := s.db.Exec(r.Context(), `
		UPDATE creatures SET nickname = $3 WHERE token_id = $1 AND lower(owner_address) = lower($2)`,
		tokenID, wallet, nickname)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if ct.RowsAffected() == 0 {
		writeError(w, http.StatusForbidden, errors.New("you don't own this creature"))
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"nickname": nickname})
}

// handleSetEggNickname is the same idea for an unhatched egg.
func (s *Server) handleSetEggNickname(w http.ResponseWriter, r *http.Request) {
	wallet := chi.URLParam(r, "wallet")
	tokenID, err := strconv.ParseInt(chi.URLParam(r, "tokenId"), 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, errors.New("invalid tokenId"))
		return
	}
	nickname, err := parseNicknameBody(r)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	ct, err := s.db.Exec(r.Context(), `
		UPDATE eggs SET nickname = $3 WHERE token_id = $1 AND lower(owner_address) = lower($2)`,
		tokenID, wallet, nickname)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if ct.RowsAffected() == 0 {
		writeError(w, http.StatusForbidden, errors.New("you don't own this egg"))
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"nickname": nickname})
}

func (s *Server) handleDailyLogin(w http.ResponseWriter, r *http.Request) {
	wallet := chi.URLParam(r, "wallet")
	if err := s.task.RecordDailyLogin(r.Context(), wallet); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// handleGetDex returns every species in the game (0..TotalSpeciesCount-1) with whether this
// player has ever owned one (species_dex is a permanent ledger -- it doesn't forget a species
// once discovered, even after the creature that earned it is sold or dies) and how many they
// currently hold live.
func (s *Server) handleGetDex(w http.ResponseWriter, r *http.Request) {
	wallet := chi.URLParam(r, "wallet")

	rows, err := s.db.Query(r.Context(), `
		SELECT s.species, sd.discovered_at, COALESCE(c.owned_count, 0)
		FROM generate_series(0, $2) AS s(species)
		LEFT JOIN species_dex sd ON sd.wallet_address = $1 AND sd.species = s.species
		LEFT JOIN (
			SELECT species, COUNT(*) AS owned_count
			FROM creatures WHERE owner_address = $1 AND NOT is_dead
			GROUP BY species
		) c ON c.species = s.species
		ORDER BY s.species`,
		wallet, models.TotalSpeciesCount-1)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	defer rows.Close()

	var out []models.DexEntry
	for rows.Next() {
		var e models.DexEntry
		if err := rows.Scan(&e.Species, &e.DiscoveredAt, &e.OwnedCount); err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		e.Discovered = e.DiscoveredAt != nil
		out = append(out, e)
	}
	writeJSON(w, http.StatusOK, out)
}

// handleFightBattle resolves one Battle Arena duel: the player's creature vs. a freshly rolled
// wild opponent. See internal/services/battle for the combat simulation.
func (s *Server) handleFightBattle(w http.ResponseWriter, r *http.Request) {
	wallet := chi.URLParam(r, "wallet")

	var body struct {
		CreatureTokenID int64 `json:"creatureTokenId"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, errors.New("invalid request body"))
		return
	}

	result, err := s.battle.Fight(r.Context(), wallet, body.CreatureTokenID)
	if err != nil {
		switch {
		case errors.Is(err, battle.ErrCreatureNotFound):
			writeError(w, http.StatusNotFound, err)
		case errors.Is(err, battle.ErrNotOwner), errors.Is(err, battle.ErrCreatureDead):
			writeError(w, http.StatusConflict, err)
		default:
			writeError(w, http.StatusInternalServerError, err)
		}
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (s *Server) handleListBattles(w http.ResponseWriter, r *http.Request) {
	wallet := chi.URLParam(r, "wallet")
	history, err := s.battle.History(r.Context(), wallet, 20)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, history)
}

func writeChallengeError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, battle.ErrChallengeNotFound), errors.Is(err, battle.ErrCreatureNotFound):
		writeError(w, http.StatusNotFound, err)
	case errors.Is(err, battle.ErrNotTargeted):
		writeError(w, http.StatusForbidden, err)
	case errors.Is(err, battle.ErrInvalidWager):
		writeError(w, http.StatusBadRequest, err)
	case errors.Is(err, battle.ErrNotOwner), errors.Is(err, battle.ErrCreatureDead),
		errors.Is(err, battle.ErrChallengeNotOpen), errors.Is(err, battle.ErrChallengeExpired),
		errors.Is(err, battle.ErrOwnChallenge), errors.Is(err, battle.ErrNotChallenger),
		errors.Is(err, battle.ErrEscrowNotFunded), errors.Is(err, battle.ErrEscrowMismatch):
		writeError(w, http.StatusConflict, err)
	default:
		writeError(w, http.StatusInternalServerError, err)
	}
}

func (s *Server) handleCreateChallenge(w http.ResponseWriter, r *http.Request) {
	wallet := chi.URLParam(r, "wallet")
	var body struct {
		CreatureTokenID  int64  `json:"creatureTokenId"`
		ChallengedWallet string `json:"challengedWallet"`
		WagerWei         string `json:"wagerWei"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, errors.New("invalid request body"))
		return
	}
	challenge, err := s.battle.CreateChallenge(r.Context(), wallet, body.CreatureTokenID, body.ChallengedWallet, body.WagerWei)
	if err != nil {
		writeChallengeError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, challenge)
}

// handleConfirmEscrow is called after the challenger's createEscrow() transaction on BattleEscrow
// mines -- the backend re-reads the escrow from the chain itself before treating the challenge as
// actually open to accept.
func (s *Server) handleConfirmEscrow(w http.ResponseWriter, r *http.Request) {
	wallet := chi.URLParam(r, "wallet")
	challengeID, err := strconv.ParseInt(chi.URLParam(r, "challengeId"), 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, errors.New("invalid challenge id"))
		return
	}
	challenge, err := s.battle.ConfirmEscrow(r.Context(), wallet, challengeID)
	if err != nil {
		writeChallengeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, challenge)
}

func (s *Server) handleMyChallenges(w http.ResponseWriter, r *http.Request) {
	wallet := chi.URLParam(r, "wallet")
	challenges, err := s.battle.MyChallenges(r.Context(), wallet, 20)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, challenges)
}

// handleIncomingChallenges lists direct challenges addressed to this wallet -- polled once on
// page load/reconnect as a fallback for whatever the websocket push missed while disconnected.
func (s *Server) handleIncomingChallenges(w http.ResponseWriter, r *http.Request) {
	wallet := chi.URLParam(r, "wallet")
	challenges, err := s.battle.IncomingChallenges(r.Context(), wallet)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, challenges)
}

// handleArenaWebSocket upgrades to a live push channel for this wallet: "challenge_received" when
// someone targets them with a direct challenge, "challenge_resolved" when their own challenge
// gets accepted. Purely additive -- every event it carries is also discoverable by polling
// IncomingChallenges/MyChallenges, so a dropped connection just falls back to that.
func (s *Server) handleArenaWebSocket(w http.ResponseWriter, r *http.Request) {
	if s.hub == nil {
		writeError(w, http.StatusServiceUnavailable, errors.New("realtime hub not configured"))
		return
	}
	wallet := chi.URLParam(r, "wallet")
	s.hub.ServeWS(w, r, wallet)
}

func (s *Server) handleAcceptChallenge(w http.ResponseWriter, r *http.Request) {
	wallet := chi.URLParam(r, "wallet")
	challengeID, err := strconv.ParseInt(chi.URLParam(r, "challengeId"), 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, errors.New("invalid challenge id"))
		return
	}
	var body struct {
		CreatureTokenID int64 `json:"creatureTokenId"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, errors.New("invalid request body"))
		return
	}
	result, err := s.battle.AcceptChallenge(r.Context(), wallet, challengeID, body.CreatureTokenID)
	if err != nil {
		writeChallengeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (s *Server) handleCancelChallenge(w http.ResponseWriter, r *http.Request) {
	wallet := chi.URLParam(r, "wallet")
	challengeID, err := strconv.ParseInt(chi.URLParam(r, "challengeId"), 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, errors.New("invalid challenge id"))
		return
	}
	if err := s.battle.CancelChallenge(r.Context(), wallet, challengeID); err != nil {
		writeChallengeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "cancelled"})
}

func (s *Server) handleOpenChallenges(w http.ResponseWriter, r *http.Request) {
	challenges, err := s.battle.OpenChallenges(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, challenges)
}

func (s *Server) handleArenaHeartbeat(w http.ResponseWriter, r *http.Request) {
	wallet := chi.URLParam(r, "wallet")
	if err := s.battle.Heartbeat(r.Context(), wallet); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) handleArenaOnline(w http.ResponseWriter, r *http.Request) {
	online, err := s.battle.OnlineWallets(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, online)
}

func (s *Server) handleListTasks(w http.ResponseWriter, r *http.Request) {
	wallet := chi.URLParam(r, "wallet")
	tasks, err := s.task.ListTasks(r.Context(), wallet)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, tasks)
}

func (s *Server) handleClaimTask(w http.ResponseWriter, r *http.Request) {
	wallet := chi.URLParam(r, "wallet")
	taskID := chi.URLParam(r, "taskId")

	txHash, err := s.task.ClaimReward(r.Context(), wallet, taskID)
	if err != nil {
		switch {
		case errors.Is(err, task.ErrNotCompleted), errors.Is(err, task.ErrAlreadyClaimed), errors.Is(err, task.ErrTaskNotFound),
			errors.Is(err, task.ErrTaskNotFunded):
			writeError(w, http.StatusConflict, err)
		default:
			writeError(w, http.StatusInternalServerError, err)
		}
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"txHash": txHash})
}

// handleCreateTask lets any wallet define a new "partner" quest -- e.g. a protocol that wants
// EggFarm players to go try theirs. Permissionless but bounded: no approval step, just hard caps
// on reward/target/duration (see task.CreateTask) so it can't be used to spam the quest board or
// drain the $FEED supply.
func (s *Server) handleCreateTask(w http.ResponseWriter, r *http.Request) {
	var body struct {
		CreatorAddress    string `json:"creatorAddress"`
		Title             string `json:"title"`
		Description       string `json:"description"`
		CheckType         string `json:"checkType"`
		ContractAddress   string `json:"contractAddress"`
		ThresholdWei      string `json:"thresholdWei"`
		FunctionSignature string `json:"functionSignature"`
		OutputType        string `json:"outputType"`
		EventSignature    string `json:"eventSignature"`
		WalletTopicIndex  int    `json:"walletTopicIndex"`
		TargetCount       int    `json:"targetCount"`
		RewardFeedWhole   int    `json:"rewardFeedWhole"`
		DurationDays      int    `json:"durationDays"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, errors.New("invalid request body"))
		return
	}
	if body.CreatorAddress == "" {
		writeError(w, http.StatusBadRequest, errors.New("creatorAddress is required"))
		return
	}

	taskID, err := s.task.CreateTask(r.Context(), task.CreateTaskInput{
		CreatorAddress:    body.CreatorAddress,
		Title:             body.Title,
		Description:       body.Description,
		CheckType:         body.CheckType,
		ContractAddress:   body.ContractAddress,
		ThresholdWei:      body.ThresholdWei,
		FunctionSignature: body.FunctionSignature,
		OutputType:        body.OutputType,
		EventSignature:    body.EventSignature,
		WalletTopicIndex:  body.WalletTopicIndex,
		TargetCount:       body.TargetCount,
		RewardFeedWhole:   body.RewardFeedWhole,
		DurationDays:      body.DurationDays,
	})
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]string{"taskId": taskID})
}

// handleFundTask lets a partner quest's creator pay to supply its $FEED reward pool -- the
// payment (native currency, sent by the caller directly to the treasury address before calling
// this) is what lets the platform earn from partner quests existing at all. Body carries the
// resulting tx hash; the backend verifies it on-chain rather than trusting a client-supplied
// amount.
func (s *Server) handleFundTask(w http.ResponseWriter, r *http.Request) {
	taskID := chi.URLParam(r, "taskId")
	var body struct {
		FunderAddress string `json:"funderAddress"`
		TxHash        string `json:"txHash"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, errors.New("invalid request body"))
		return
	}
	if body.FunderAddress == "" || body.TxHash == "" {
		writeError(w, http.StatusBadRequest, errors.New("funderAddress and txHash are required"))
		return
	}

	feedCredited, err := s.task.FundTask(r.Context(), taskID, body.FunderAddress, body.TxHash)
	if err != nil {
		switch {
		case errors.Is(err, task.ErrTaskNotFound):
			writeError(w, http.StatusNotFound, err)
		case errors.Is(err, task.ErrNotPartnerTask), errors.Is(err, task.ErrPaymentUnverified), errors.Is(err, task.ErrPaymentAlreadyUsed):
			writeError(w, http.StatusConflict, err)
		default:
			writeError(w, http.StatusInternalServerError, err)
		}
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"feedCredited": feedCredited.String()})
}

// handleFeedShopPackages lists the fixed catalog of pre-made $FEED bags.
func (s *Server) handleFeedShopPackages(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, shop.Packages)
}

// handleFeedShopPurchase credits a $FEED package after verifying the buyer's payment landed on
// the treasury on-chain -- another platform revenue stream alongside the wager rake and partner
// quest funding.
func (s *Server) handleFeedShopPurchase(w http.ResponseWriter, r *http.Request) {
	var body struct {
		BuyerAddress string `json:"buyerAddress"`
		PackageID    string `json:"packageId"`
		TxHash       string `json:"txHash"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, errors.New("invalid request body"))
		return
	}
	if body.BuyerAddress == "" || body.PackageID == "" || body.TxHash == "" {
		writeError(w, http.StatusBadRequest, errors.New("buyerAddress, packageId, and txHash are required"))
		return
	}

	feedCredited, err := s.shop.Purchase(r.Context(), body.BuyerAddress, body.PackageID, body.TxHash)
	if err != nil {
		switch {
		case errors.Is(err, shop.ErrPackageNotFound):
			writeError(w, http.StatusNotFound, err)
		case errors.Is(err, shop.ErrPaymentUnverified), errors.Is(err, shop.ErrPaymentTooLow), errors.Is(err, shop.ErrPaymentAlreadyUsed):
			writeError(w, http.StatusConflict, err)
		default:
			writeError(w, http.StatusInternalServerError, err)
		}
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"feedCredited": feedCredited.String()})
}

// handleEggPreview shows the player their egg odds before they spend gas laying one. Query
// params: rarity (parent creature rarity 1-5), happiness (0-100).
func (s *Server) handleEggPreview(w http.ResponseWriter, r *http.Request) {
	happiness, err := strconv.Atoi(r.URL.Query().Get("happiness"))
	if err != nil {
		writeError(w, http.StatusBadRequest, errors.New("happiness query param must be an integer 0-100"))
		return
	}
	writeJSON(w, http.StatusOK, rng.OddsForHappiness(happiness))
}

func (s *Server) handleListListings(w http.ResponseWriter, r *http.Request) {
	kind := r.URL.Query().Get("kind")     // "egg" | "creature" | "" (both)
	seller := r.URL.Query().Get("seller") // set for "my listings": every status, not just active

	// Left-joined against whichever of creatures/eggs matches this listing's kind, so the
	// marketplace cards can show real rarity/species art instead of a generic placeholder.
	// Token IDs aren't globally unique (CreatureNFT and EggNFT each count from 1 independently),
	// so the join is gated on kind to avoid matching the wrong contract's token.
	query := `
		SELECT l.listing_id, l.nft_contract, l.token_id, l.kind, l.seller_address, l.price_wei,
		       l.is_active, l.listed_at, l.sold_at, l.buyer_address,
		       COALESCE(c.rarity, e.rarity), COALESCE(c.species, e.species), c.care_score, c.happiness,
		       COALESCE(c.nickname, e.nickname)
		FROM listings l
		LEFT JOIN creatures c ON l.kind = 'creature' AND c.token_id = l.token_id
		LEFT JOIN eggs e ON l.kind = 'egg' AND e.token_id = l.token_id
		WHERE `
	args := []interface{}{}
	if seller != "" {
		query += `lower(l.seller_address) = lower($1)`
		args = append(args, seller)
		if kind != "" {
			query += ` AND l.kind = $2`
			args = append(args, kind)
		}
		query += ` ORDER BY l.listed_at DESC LIMIT 200`
	} else {
		query += `l.is_active = true`
		if kind != "" {
			query += ` AND l.kind = $1`
			args = append(args, kind)
		}
		query += ` ORDER BY l.price_wei ASC LIMIT 200`
	}

	rows, err := s.db.Query(r.Context(), query, args...)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	defer rows.Close()

	var out []models.Listing
	for rows.Next() {
		var l models.Listing
		if err := rows.Scan(&l.ListingID, &l.NFTContract, &l.TokenID, &l.Kind, &l.SellerAddress, &l.PriceWei,
			&l.IsActive, &l.ListedAt, &l.SoldAt, &l.BuyerAddress, &l.Rarity, &l.Species, &l.CareScore, &l.Happiness, &l.Nickname); err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		out = append(out, l)
	}
	if err := s.attachListingAbilities(r.Context(), out); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	// "Hot" is only meaningful for the general browse view, not a seller's own listing history.
	if seller == "" {
		s.markHotListing(r.Context(), out)
	}
	writeJSON(w, http.StatusOK, out)
}

// markHotListing flags exactly one active listing as the marketplace's "hot" pick: the cheapest
// active listing of whichever (kind, species) sold the most in the last 7 days. Falls back to the
// single highest-rarity active listing (lowest listing_id breaks ties) when nothing's sold yet, so
// there's always a featured item to show even on a brand new marketplace.
func (s *Server) markHotListing(ctx context.Context, listings []models.Listing) {
	if len(listings) == 0 {
		return
	}

	var hotKind string
	var hotSpecies int16
	err := s.db.QueryRow(ctx, `
		SELECT l.kind, COALESCE(c.species, e.species) AS species
		FROM listings l
		LEFT JOIN creatures c ON l.kind = 'creature' AND c.token_id = l.token_id
		LEFT JOIN eggs e ON l.kind = 'egg' AND e.token_id = l.token_id
		WHERE l.sold_at IS NOT NULL AND l.sold_at > now() - interval '7 days'
		GROUP BY l.kind, COALESCE(c.species, e.species)
		ORDER BY count(*) DESC
		LIMIT 1`).Scan(&hotKind, &hotSpecies)

	if err == nil {
		var cheapest *models.Listing
		for i := range listings {
			l := &listings[i]
			if l.Kind != hotKind || l.Species == nil || *l.Species != hotSpecies {
				continue
			}
			if cheapest == nil {
				cheapest = l
			}
		}
		if cheapest != nil {
			cheapest.Hot = true
			return
		}
	}

	// Fallback: no recent sales (or none currently listed) -- feature the rarest active listing.
	var rarest *models.Listing
	for i := range listings {
		l := &listings[i]
		if l.Rarity == nil {
			continue
		}
		if rarest == nil || *l.Rarity > *rarest.Rarity {
			rarest = l
		}
	}
	if rarest != nil {
		rarest.Hot = true
	}
}

// attachListingAbilities fills in Abilities for the creature-kind listings in one query.
func (s *Server) attachListingAbilities(ctx context.Context, listings []models.Listing) error {
	ids := make([]int64, 0, len(listings))
	byID := map[int64][]*models.Listing{}
	for i := range listings {
		if listings[i].Kind != "creature" {
			continue
		}
		ids = append(ids, listings[i].TokenID)
		byID[listings[i].TokenID] = append(byID[listings[i].TokenID], &listings[i])
	}
	if len(ids) == 0 {
		return nil
	}
	rows, err := s.db.Query(ctx, `
		SELECT creature_token_id, ability_key FROM creature_abilities
		WHERE creature_token_id = ANY($1) ORDER BY acquired_at`, ids)
	if err != nil {
		return fmt.Errorf("attaching listing abilities: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var tokenID int64
		var key string
		if err := rows.Scan(&tokenID, &key); err != nil {
			return err
		}
		for _, l := range byID[tokenID] {
			l.Abilities = append(l.Abilities, key)
		}
	}
	return rows.Err()
}

// handleAbilityCatalog returns the full ability catalog (name/description/effects) so clients can
// resolve the ability keys attached to creatures/listings into something displayable, without
// repeating that catalog in every creature payload.
func (s *Server) handleAbilityCatalog(w http.ResponseWriter, r *http.Request) {
	out := make([]models.Ability, 0, len(models.AbilityCatalog))
	for _, a := range models.AbilityCatalog {
		out = append(out, a)
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) handleLeaderboard(w http.ResponseWriter, r *http.Request) {
	rows, err := s.db.Query(r.Context(), `
		SELECT seller_address, COUNT(*) AS sales, SUM(price_wei) AS total_wei
		FROM listings
		WHERE sold_at IS NOT NULL
		GROUP BY seller_address
		ORDER BY total_wei DESC
		LIMIT 50`)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	defer rows.Close()

	type row struct {
		Wallet   string `json:"wallet"`
		Sales    int    `json:"sales"`
		TotalWei string `json:"totalWei"`
	}
	var out []row
	for rows.Next() {
		var rr row
		if err := rows.Scan(&rr.Wallet, &rr.Sales, &rr.TotalWei); err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		out = append(out, rr)
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) handleBattleLeaderboard(w http.ResponseWriter, r *http.Request) {
	rows, err := s.db.Query(r.Context(), `
		SELECT wallet_address, COUNT(*) FILTER (WHERE won) AS wins, COUNT(*) AS total
		FROM battles
		GROUP BY wallet_address
		HAVING COUNT(*) FILTER (WHERE won) > 0
		ORDER BY wins DESC, total ASC
		LIMIT 50`)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	defer rows.Close()

	type row struct {
		Wallet string `json:"wallet"`
		Wins   int    `json:"wins"`
		Total  int    `json:"total"`
	}
	var out []row
	for rows.Next() {
		var rr row
		if err := rows.Scan(&rr.Wallet, &rr.Wins, &rr.Total); err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		out = append(out, rr)
	}
	writeJSON(w, http.StatusOK, out)
}

// handleActivity gives a player a unified view of everything that's moved money on their
// account: battle results (PvE + PvP, $FEED), wagered PvP duels (native currency, via
// BattleEscrow), and their own platform-facing transactions (Feed Shop purchases, quest funding
// payments, and the rake taken from a wager they lost). Three separate lists rather than one
// merged/sorted feed -- each has a different shape, and interleaving them loses more clarity than
// it gains.
func (s *Server) handleActivity(w http.ResponseWriter, r *http.Request) {
	wallet := chi.URLParam(r, "wallet")
	ctx := r.Context()

	type battleEntry struct {
		CreatureTokenID int64     `json:"creatureTokenId"`
		OpponentSpecies int16     `json:"opponentSpecies"`
		OpponentRarity  int16     `json:"opponentRarity"`
		Won             bool      `json:"won"`
		RewardFeed      string    `json:"rewardFeed"`
		CreatedAt       time.Time `json:"createdAt"`
	}
	battleRows, err := s.db.Query(ctx, `
		SELECT creature_token_id, opponent_species, opponent_rarity, won, reward_feed, created_at
		FROM battles WHERE wallet_address = $1 ORDER BY created_at DESC LIMIT 30`, wallet)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	battles := []battleEntry{}
	for battleRows.Next() {
		var b battleEntry
		if err := battleRows.Scan(&b.CreatureTokenID, &b.OpponentSpecies, &b.OpponentRarity, &b.Won, &b.RewardFeed, &b.CreatedAt); err != nil {
			battleRows.Close()
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		battles = append(battles, b)
	}
	battleRows.Close()
	if err := battleRows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}

	type wagerEntry struct {
		ChallengeID     int64     `json:"challengeId"`
		OpponentWallet  string    `json:"opponentWallet"`
		WagerWei        string    `json:"wagerWei"`
		Won             bool      `json:"won"`
		EscrowResolveTx *string   `json:"escrowResolveTx,omitempty"`
		ResolvedAt      time.Time `json:"resolvedAt"`
	}
	wagerRows, err := s.db.Query(ctx, `
		SELECT id,
		       CASE WHEN challenger_wallet = $1 THEN opponent_wallet ELSE challenger_wallet END,
		       wager_wei, winner_wallet, escrow_resolve_tx, resolved_at
		FROM battle_challenges
		WHERE status = 'completed' AND wager_wei != '0' AND (challenger_wallet = $1 OR opponent_wallet = $1)
		ORDER BY resolved_at DESC LIMIT 30`, wallet)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	wagers := []wagerEntry{}
	for wagerRows.Next() {
		var e wagerEntry
		var opponentWallet *string
		var winnerWallet *string
		if err := wagerRows.Scan(&e.ChallengeID, &opponentWallet, &e.WagerWei, &winnerWallet, &e.EscrowResolveTx, &e.ResolvedAt); err != nil {
			wagerRows.Close()
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		if opponentWallet != nil {
			e.OpponentWallet = *opponentWallet
		}
		e.Won = winnerWallet != nil && strings.EqualFold(*winnerWallet, wallet)
		wagers = append(wagers, e)
	}
	wagerRows.Close()
	if err := wagerRows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}

	type platformTxEntry struct {
		Source          string    `json:"source"`
		NativeAmountWei string    `json:"nativeAmountWei"`
		FeedAmount      string    `json:"feedAmount"`
		TaskID          *string   `json:"taskId,omitempty"`
		CreatedAt       time.Time `json:"createdAt"`
	}
	txRows, err := s.db.Query(ctx, `
		SELECT source, native_amount_wei, feed_amount, task_id, created_at
		FROM platform_revenue WHERE wallet_address = $1 ORDER BY created_at DESC LIMIT 30`, wallet)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	platformTx := []platformTxEntry{}
	for txRows.Next() {
		var e platformTxEntry
		if err := txRows.Scan(&e.Source, &e.NativeAmountWei, &e.FeedAmount, &e.TaskID, &e.CreatedAt); err != nil {
			txRows.Close()
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		platformTx = append(platformTx, e)
	}
	txRows.Close()
	if err := txRows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}

	walletEvents, err := s.fetchWalletEvents(ctx, wallet)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"battles":      battles,
		"wagers":       wagers,
		"platformTx":   platformTx,
		"walletEvents": walletEvents,
	})
}

// fetchWalletEvents returns a wallet's generic activity feed (native-balance changes,
// marketplace trades) -- see migrations/0016_wallet_events.sql.
func (s *Server) fetchWalletEvents(ctx context.Context, wallet string) ([]models.WalletEvent, error) {
	rows, err := s.db.Query(ctx, `
		SELECT id, kind, message, amount_wei, created_at
		FROM wallet_events WHERE lower(wallet_address) = lower($1)
		ORDER BY created_at DESC LIMIT 30`, wallet)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []models.WalletEvent{}
	for rows.Next() {
		var e models.WalletEvent
		if err := rows.Scan(&e.ID, &e.Kind, &e.Message, &e.AmountWei, &e.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

func writeJSON(w http.ResponseWriter, status int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		slog.Error("writing JSON response failed", "error", err)
	}
}

func writeError(w http.ResponseWriter, status int, err error) {
	writeJSON(w, status, map[string]string{"error": err.Error()})
}
