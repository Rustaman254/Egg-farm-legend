-- feed_balance_cached was never written anywhere after row creation, so it always read back 0
-- regardless of a player's real $FEED balance. /api/players/{wallet}/farm now reads the balance
-- live from FeedToken.balanceOf() instead; drop the misleading column.
ALTER TABLE players DROP COLUMN feed_balance_cached;
