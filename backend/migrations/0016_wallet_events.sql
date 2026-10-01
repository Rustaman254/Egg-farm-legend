-- Generic "something happened to your wallet" feed: native-balance changes (detected by the
-- Wallet Watcher service while a player is connected) and marketplace trades (posted by the
-- Marketplace Indexer). Distinct from battles/wagers/platform_revenue (which already have their
-- own typed tables) -- this is the catch-all the Activity screen and the live websocket toast
-- both read from, so a player never has to wonder "did something just happen to my wallet?".
CREATE TABLE wallet_events (
    id             BIGSERIAL PRIMARY KEY,
    wallet_address  TEXT NOT NULL REFERENCES players(wallet_address),
    kind             TEXT NOT NULL CHECK (kind IN ('balance_up', 'balance_down', 'listing_sold', 'listing_bought')),
    message           TEXT NOT NULL,
    amount_wei         NUMERIC(38, 0),
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_wallet_events_wallet ON wallet_events(wallet_address, created_at DESC);
