-- Platform revenue: a rake on PvP wagers, and protocols buying $FEED to fund their partner
-- quests. Both land in TREASURY_ADDRESS on-chain; this table is the off-chain audit trail
-- (see internal/services/battle.AcceptChallenge and internal/services/task.FundTask).
CREATE TABLE platform_revenue (
    id               BIGSERIAL PRIMARY KEY,
    source            TEXT NOT NULL CHECK (source IN ('wager_rake', 'quest_funding')),
    wallet_address     TEXT NOT NULL, -- who paid (loser-side wallet for a rake, funder for quest funding)
    tx_hash             TEXT,          -- the funder's own payment tx, for quest_funding only
    native_amount_wei    NUMERIC(38, 0) NOT NULL DEFAULT 0,
    feed_amount           NUMERIC(38, 0) NOT NULL DEFAULT 0,
    task_id                TEXT REFERENCES tasks(id),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- A funder's payment tx can only ever be credited once.
CREATE UNIQUE INDEX idx_platform_revenue_tx_hash ON platform_revenue (tx_hash) WHERE tx_hash IS NOT NULL;

-- funded_feed tracks how much of a partner quest's reward pool a protocol has actually paid for;
-- ClaimReward checks against it (for creator_address-having tasks only -- built-in daily quests
-- aren't gated) and draws it down per claim. Irrelevant (stays 0) for built-in tasks.
ALTER TABLE tasks ADD COLUMN funded_feed NUMERIC(38, 0) NOT NULL DEFAULT 0;
