-- Species dex: a permanent "have I ever owned this species" ledger per player, Pokedex-style.
-- Deliberately separate from `creatures` (which only reflects current live ownership) -- a dex
-- entry must stay "discovered" even after the creature that earned it is sold, dies, or is bred
-- away, exactly like a real Pokedex never forgets a species you've caught.
CREATE TABLE species_dex (
    wallet_address   TEXT NOT NULL REFERENCES players(wallet_address),
    species           SMALLINT NOT NULL,
    first_token_id     BIGINT NOT NULL,
    discovered_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (wallet_address, species)
);
CREATE INDEX idx_species_dex_wallet ON species_dex(wallet_address);
