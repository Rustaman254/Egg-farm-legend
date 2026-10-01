-- EggFarm Legends core schema.
-- Players, creatures, and eggs are cached/derived from on-chain state (source of truth is the
-- smart contracts); Postgres exists so the Flutter app and leaderboard can query cheaply and
-- offline-first without hammering an RPC node. Tasks, task completions, and marketplace listings
-- are indexed the same way -- listings mirror Marketplace.sol events.

CREATE TABLE players (
    wallet_address      TEXT PRIMARY KEY,
    display_name        TEXT,
    feed_balance_cached  NUMERIC(38, 0) NOT NULL DEFAULT 0,
    last_login_at        TIMESTAMPTZ,
    login_streak_days    INTEGER NOT NULL DEFAULT 0,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE creatures (
    token_id             BIGINT PRIMARY KEY,
    owner_address         TEXT NOT NULL REFERENCES players(wallet_address),
    species               SMALLINT NOT NULL,
    rarity                SMALLINT NOT NULL,
    breed_count            SMALLINT NOT NULL DEFAULT 0,
    happiness              SMALLINT NOT NULL DEFAULT 50,
    birth_time              TIMESTAMPTZ NOT NULL,
    last_fed_at             TIMESTAMPTZ NOT NULL,
    last_egg_at              TIMESTAMPTZ,
    is_dead                  BOOLEAN NOT NULL DEFAULT false,
    hunger_zero_since         TIMESTAMPTZ,
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_creatures_owner ON creatures(owner_address) WHERE NOT is_dead;

CREATE TABLE eggs (
    token_id       BIGINT PRIMARY KEY,
    owner_address   TEXT NOT NULL REFERENCES players(wallet_address),
    rarity          SMALLINT NOT NULL,
    species         SMALLINT NOT NULL,
    hatch_time       TIMESTAMPTZ NOT NULL,
    parent1          BIGINT,
    parent2          BIGINT,
    is_rotten         BOOLEAN NOT NULL DEFAULT false,
    is_hatched         BOOLEAN NOT NULL DEFAULT false,
    laid_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_eggs_owner ON eggs(owner_address) WHERE NOT is_hatched;

CREATE TABLE tasks (
    id            TEXT PRIMARY KEY,          -- e.g. 'feed_3_times'
    title          TEXT NOT NULL,
    description     TEXT NOT NULL,
    target_count     INTEGER NOT NULL,
    reward_feed       NUMERIC(38, 0) NOT NULL, -- 18-decimal FEED amount
    is_active          BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE task_progress (
    wallet_address   TEXT NOT NULL REFERENCES players(wallet_address),
    task_id           TEXT NOT NULL REFERENCES tasks(id),
    progress_date      DATE NOT NULL,          -- resets daily at 00:00 UTC
    current_count       INTEGER NOT NULL DEFAULT 0,
    completed_at          TIMESTAMPTZ,
    reward_claimed          BOOLEAN NOT NULL DEFAULT false,
    PRIMARY KEY (wallet_address, task_id, progress_date)
);

CREATE TABLE listings (
    listing_id       BIGINT PRIMARY KEY,       -- on-chain listingId
    nft_contract      TEXT NOT NULL,
    token_id           BIGINT NOT NULL,
    kind                TEXT NOT NULL CHECK (kind IN ('egg', 'creature')),
    seller_address        TEXT NOT NULL,
    price_wei              NUMERIC(38, 0) NOT NULL,
    is_active                BOOLEAN NOT NULL DEFAULT true,
    listed_at                 TIMESTAMPTZ NOT NULL,
    sold_at                    TIMESTAMPTZ,
    buyer_address                TEXT,
    cancelled_at                  TIMESTAMPTZ,
    tx_hash                        TEXT NOT NULL
);
CREATE INDEX idx_listings_active ON listings(kind, is_active, price_wei);
CREATE INDEX idx_listings_seller ON listings(seller_address);

CREATE TABLE indexer_cursor (
    contract_name   TEXT PRIMARY KEY,
    last_block        BIGINT NOT NULL
);

-- Seed the default daily task catalog.
INSERT INTO tasks (id, title, description, target_count, reward_feed) VALUES
    ('feed_3_times',   'Feed 3 Times',      'Feed any of your creatures 3 times today',        3, 15000000000000000000),
    ('collect_1_egg',  'Collect 1 Egg',     'Collect at least 1 egg from your farm',            1, 20000000000000000000),
    ('daily_login',    'Daily Login',       'Open the app today',                               1, 50000000000000000000),
    ('list_1_item',    'List an Item',      'List an egg or creature on the marketplace',       1, 10000000000000000000),
    ('play_minigame',  'Play a Mini-Game',  'Complete one round of a mini-game',                1, 10000000000000000000);
