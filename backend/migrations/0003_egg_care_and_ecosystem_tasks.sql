-- Egg incubation care (mirrors EggNFT.sol's new careLevel/lastCaredAt/careZeroSince fields).
ALTER TABLE eggs
    ADD COLUMN care_level        SMALLINT NOT NULL DEFAULT 100,
    ADD COLUMN last_cared_at       TIMESTAMPTZ,
    ADD COLUMN care_zero_since       TIMESTAMPTZ;

-- Ecosystem tasks: real on-chain activity on Arbitrum, verified without relying on the player's
-- client to self-report. `check_type` picks the verification strategy:
--   'manual'          -- completed via RecordProgress calls from our own game-event indexers
--                         (feed_3_times, collect_1_egg, list_1_item, daily_login already work
--                         this way; see internal/services/task)
--   'native_balance'  -- wallet's ETH balance on Arbitrum >= threshold_wei
--   'token_balance'   -- wallet's balanceOf(contract_address) >= threshold_wei (e.g. ARB token)
--   'tx_count'        -- wallet's transaction count on Arbitrum >= threshold_count
--   'token_received'  -- wallet appears as `to` in a Transfer event on contract_address
ALTER TABLE tasks
    ADD COLUMN check_type        TEXT NOT NULL DEFAULT 'manual'
        CHECK (check_type IN ('manual', 'native_balance', 'token_balance', 'tx_count', 'token_received')),
    ADD COLUMN contract_address   TEXT,
    ADD COLUMN threshold_wei       NUMERIC(38, 0),
    ADD COLUMN threshold_count       INTEGER,
    ADD COLUMN deploy_block             BIGINT NOT NULL DEFAULT 0;

-- Seed the ecosystem task catalog. `contract_address` for the ARB-token-based tasks is left NULL
-- here since the real ARB governance token isn't deployed on every network this project might
-- run against (e.g. Arbitrum Sepolia/local Anvil don't have it) -- cmd/worker fills it in from
-- the ARB_TOKEN_ADDRESS env var at startup if configured, and the task simply stays inactive
-- (never completable) on networks where it isn't.
INSERT INTO tasks (id, title, description, target_count, reward_feed, check_type, threshold_wei) VALUES
    ('arb_holder', 'Arbitrum Holder', 'Hold at least 0.01 ETH in your wallet on Arbitrum', 1, 30000000000000000000, 'native_balance', 10000000000000000);

INSERT INTO tasks (id, title, description, target_count, reward_feed, check_type, threshold_count) VALUES
    ('active_wallet', 'Active on Arbitrum', 'Make at least 3 transactions on Arbitrum', 1, 30000000000000000000, 'tx_count', 3);

INSERT INTO tasks (id, title, description, target_count, reward_feed, check_type, threshold_wei) VALUES
    ('arb_token_holder', 'ARB Token Holder', 'Hold at least 1 $ARB governance token', 1, 50000000000000000000, 'token_balance', 1000000000000000000);

INSERT INTO tasks (id, title, description, target_count, reward_feed, check_type) VALUES
    ('arb_token_received', 'Received ARB', 'Receive an ARB token transfer to your wallet', 1, 20000000000000000000, 'token_received');
