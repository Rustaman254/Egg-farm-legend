-- Two more generic check_types so Community Quests can target *any* protocol, not just ones
-- shaped like an ERC-20 (token_balance/token_received) or matched by "any event, any topic"
-- (contract_event, which is precise about the contract but not the action):
--
--   'view_function' -- calls an arbitrary `fn(address) returns (T)` read function the creator
--                       names (staked balance, points, tier, reputation, "isMember" ...) and
--                       compares the result to a threshold. Covers "has enough of X" for any
--                       protocol that exposes any per-wallet numeric or boolean accessor.
--   'named_event'   -- watches for one exact event (topic0 = keccak256 of the creator-given
--                       canonical signature, e.g. "Staked(address,uint256)") with the wallet in
--                       a creator-specified indexed topic slot. Covers "did this specific action"
--                       precisely, instead of contract_event's "did anything on this contract".
--
-- function_selector/event_topic0 are precomputed at creation time (task.CreateTask) so the
-- ecosystem service never needs to touch signature text at check time -- same pattern as
-- contract_address being resolved once instead of re-parsed per check.
ALTER TABLE tasks DROP CONSTRAINT tasks_check_type_check;
ALTER TABLE tasks ADD CONSTRAINT tasks_check_type_check
    CHECK (check_type IN ('manual', 'native_balance', 'token_balance', 'tx_count', 'token_received',
                           'contract_event', 'view_function', 'named_event'));

ALTER TABLE tasks
    ADD COLUMN function_signature   TEXT,
    ADD COLUMN function_selector     TEXT,
    ADD COLUMN output_type            TEXT CHECK (output_type IN ('uint8','uint16','uint32','uint64','uint128','uint256','bool')),
    ADD COLUMN event_signature          TEXT,
    ADD COLUMN event_topic0               TEXT,
    ADD COLUMN wallet_topic_index           SMALLINT CHECK (wallet_topic_index BETWEEN 1 AND 3);
