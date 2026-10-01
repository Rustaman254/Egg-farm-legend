-- Adds targeted (player-vs-specific-player) challenges and optional $FEED wagers on top of the
-- existing open challenge board. A challenge with challenged_wallet set is private to that wallet
-- (it never appears on the public /api/arena/challenges board) and is pushed to them in real time
-- over the arena websocket; NULL keeps today's "post to the open board" behavior.
ALTER TABLE battle_challenges
    ADD COLUMN challenged_wallet TEXT REFERENCES players(wallet_address),
    ADD COLUMN wager_feed NUMERIC(38, 0) NOT NULL DEFAULT 0;

CREATE INDEX idx_battle_challenges_challenged_wallet
    ON battle_challenges (challenged_wallet)
    WHERE status = 'open';
