-- Battle Arena: PvE duels against a procedurally-generated wild opponent, using each creature's
-- derived HP/Attack/Defense (same deterministic species+rarity formula the webapp renders on
-- every card). Battles aren't on-chain -- there's no reason to spend gas on a coin-flip-with-
-- flavor -- but wins mint a real $FEED reward through the same MINTER_ROLE signer path as tasks,
-- and feed the existing `play_minigame` daily task.
CREATE TABLE battles (
    id                BIGSERIAL PRIMARY KEY,
    wallet_address     TEXT NOT NULL REFERENCES players(wallet_address),
    creature_token_id   BIGINT NOT NULL,
    opponent_species      SMALLINT NOT NULL,
    opponent_rarity        SMALLINT NOT NULL,
    won                      BOOLEAN NOT NULL,
    rounds                    SMALLINT NOT NULL,
    reward_feed                NUMERIC(38, 0) NOT NULL DEFAULT 0,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_battles_wallet ON battles(wallet_address, created_at DESC);

UPDATE tasks
SET title = 'Win a Battle', description = 'Win a duel in the Battle Arena'
WHERE id = 'play_minigame';
