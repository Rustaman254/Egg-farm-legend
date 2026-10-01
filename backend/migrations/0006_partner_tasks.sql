-- Partner/community quests: anyone can create a task that rewards activity on a protocol they
-- name, not just our own game contracts. Permissionless but bounded -- no approval queue, just
-- hard caps on reward/duration/target enforced by the API (see internal/services/task
-- CreateTask) so the FEED supply and quest board can't be spammed or drained. Distinct from
-- 'ecosystem' tasks (which are curated, official, Arbitrum-wide checks like "hold ARB") even
-- though they share the same check_type machinery under the hood.
ALTER TABLE tasks
    ADD COLUMN category         TEXT NOT NULL DEFAULT 'game' CHECK (category IN ('game', 'ecosystem', 'partner')),
    ADD COLUMN creator_address   TEXT,
    ADD COLUMN expires_at         TIMESTAMPTZ,
    ADD COLUMN created_at           TIMESTAMPTZ NOT NULL DEFAULT now();

UPDATE tasks SET category = 'ecosystem'
WHERE id IN ('arb_holder', 'active_wallet', 'arb_token_holder', 'arb_token_received');

-- 'contract_event' generalizes token_received beyond ERC-20 Transfer: it credits a wallet the
-- moment it appears in ANY indexed topic of ANY log emitted by the target contract, with no
-- assumption about the event's shape. That's what makes "prove you interacted with my protocol"
-- checkable without knowing the protocol's ABI up front -- swaps, stakes, mints, and transfers
-- all index the acting address as a matter of near-universal Solidity convention.
ALTER TABLE tasks DROP CONSTRAINT tasks_check_type_check;
ALTER TABLE tasks ADD CONSTRAINT tasks_check_type_check
    CHECK (check_type IN ('manual', 'native_balance', 'token_balance', 'tx_count', 'token_received', 'contract_event'));

CREATE INDEX idx_tasks_category ON tasks(category) WHERE is_active;

-- More scenarios: two new 'game' tasks wired to real events the gamestate indexer already
-- decodes (CreaturesBred, EggTended) but previously didn't credit toward anything, plus a
-- higher-bar 'ecosystem' task for long-time Arbitrum wallets.
INSERT INTO tasks (id, title, description, target_count, reward_feed, category) VALUES
    ('breed_1_creature', 'Breed a Creature',  'Breed two of your creatures today',              1, 25000000000000000000, 'game'),
    ('tend_1_egg',       'Tend an Egg',       'Top up an egg''s incubation care today',          1, 10000000000000000000, 'game');

INSERT INTO tasks (id, title, description, target_count, reward_feed, category) VALUES
    ('win_3_battles', 'Battle Champion', 'Win 3 duels in the Battle Arena today', 3, 40000000000000000000, 'game');

INSERT INTO tasks (id, title, description, target_count, reward_feed, check_type, threshold_count, category) VALUES
    ('arbitrum_veteran', 'Arbitrum Veteran', 'Have made at least 50 transactions on Arbitrum, ever', 1, 60000000000000000000, 'tx_count', 50, 'ecosystem');
