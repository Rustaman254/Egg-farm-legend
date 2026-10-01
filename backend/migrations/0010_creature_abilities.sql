-- Creature abilities: a genesis (non-bred) creature rolls 1-3 abilities gated by its rarity;
-- a bred creature can inherit any of its parents' abilities and has a chance to mutate a brand
-- new one neither parent had. See internal/models/abilities.go for the catalog and
-- internal/services/gamestate's onEggHatched for the assignment roll.
CREATE TABLE creature_abilities (
    creature_token_id BIGINT NOT NULL REFERENCES creatures(token_id) ON DELETE CASCADE,
    ability_key        TEXT NOT NULL,
    source              TEXT NOT NULL CHECK (source IN ('genesis', 'inherited', 'mutated')),
    acquired_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (creature_token_id, ability_key)
);
