-- Adds the $FEED Shop as a third platform revenue source alongside wager_rake and quest_funding.
-- See internal/services/shop.
ALTER TABLE platform_revenue DROP CONSTRAINT platform_revenue_source_check;
ALTER TABLE platform_revenue ADD CONSTRAINT platform_revenue_source_check
    CHECK (source IN ('wager_rake', 'quest_funding', 'feed_shop'));
