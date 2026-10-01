-- Creature leveling: care_score is a plain cumulative counter, bumped by the gamestate indexer
-- every time a real CreatureFed event confirms (see onCreatureFed) -- so it's exactly as
-- forgery-proof as every other stat in this game: derived from on-chain activity, never
-- self-reported. Battle stats (internal/services/battle.Stats / webapp battleStats.ts) turn
-- this into a level and a flat HP/Attack/Defense bonus large enough that a long-cared-for Common
-- creature can eventually out-stat a neglected Legendary.
ALTER TABLE creatures ADD COLUMN care_score INTEGER NOT NULL DEFAULT 0;

-- Farmer (player) leveling: XP is awarded 1:1 alongside every $FEED reward (task claims, battle
-- wins) -- see task.ClaimReward and battle.Fight -- so it needs no separate balancing pass and
-- always tracks "how much of this game has this wallet actually done."
ALTER TABLE players ADD COLUMN xp INTEGER NOT NULL DEFAULT 0;

-- Arena presence: a simple heartbeat table, not a websocket presence system -- the Battle Arena
-- page pings its own wallet every ~20s while open, and "online" means "seen in the last 60s".
-- Good enough for "who's in the arena right now" without adding realtime infra.
CREATE TABLE arena_presence (
    wallet_address   TEXT PRIMARY KEY REFERENCES players(wallet_address),
    last_seen_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- PvP battle challenges: a challenger posts a creature to the open board; anyone else can accept
-- with one of their own. Resolution reuses the same deterministic combat sim as PvE (see
-- battle.Fight), just with two real creatures' real (leveled) stats instead of one real + one
-- procedurally-generated wild opponent.
CREATE TABLE battle_challenges (
    id                            BIGSERIAL PRIMARY KEY,
    challenger_wallet              TEXT NOT NULL REFERENCES players(wallet_address),
    challenger_creature_token_id    BIGINT NOT NULL,
    opponent_wallet                  TEXT REFERENCES players(wallet_address),
    opponent_creature_token_id        BIGINT,
    status                              TEXT NOT NULL DEFAULT 'open'
                                            CHECK (status IN ('open', 'completed', 'cancelled', 'expired')),
    winner_wallet                        TEXT,
    rounds                                SMALLINT,
    log                                    JSONB,
    reward_feed                             NUMERIC(38, 0) NOT NULL DEFAULT 0,
    created_at                               TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at                                TIMESTAMPTZ NOT NULL DEFAULT now() + interval '15 minutes',
    resolved_at                                TIMESTAMPTZ
);
CREATE INDEX idx_battle_challenges_open ON battle_challenges(status, created_at DESC) WHERE status = 'open';
CREATE INDEX idx_battle_challenges_wallet ON battle_challenges(challenger_wallet, opponent_wallet);
