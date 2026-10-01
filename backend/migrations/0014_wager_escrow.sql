-- PvP wagers move from a $FEED burn/mint (internal ledger) to a real on-chain native-currency
-- (ETH/ARB) escrow -- see contracts/src/BattleEscrow.sol. wager_feed already stored an 18-decimal
-- fixed-point amount, same as wei, so this is a rename, not a data migration.
ALTER TABLE battle_challenges RENAME COLUMN wager_feed TO wager_wei;

-- true for an unwagered challenge (nothing to escrow) or once the challenger's on-chain stake is
-- verified (see battle.Service.ConfirmEscrow); false the moment a challenge with wager_wei > 0 is
-- created and the on-chain createEscrow() call hasn't been confirmed yet -- kept off the open
-- board / incoming list until then, since nothing is actually staked before that.
ALTER TABLE battle_challenges ADD COLUMN escrow_confirmed BOOLEAN NOT NULL DEFAULT true;

-- The BattleEscrow.resolve() tx hash, once a wagered duel is settled -- audit trail for where
-- the payout actually happened on-chain.
ALTER TABLE battle_challenges ADD COLUMN escrow_resolve_tx TEXT;
