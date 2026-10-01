-- Email/password accounts for the mobile app's built-in wallet (see internal/services/auth):
-- a player registers with username/email/password, the mobile app generates an Ethereum keypair
-- locally and never sends the raw private key here -- only its password-encrypted Ethereum V3
-- keystore JSON (wallet_backup), so this account system can hand it back on login for the app to
-- decrypt client-side. The webapp's wallet-connect players never populate these columns.
ALTER TABLE players
    ADD COLUMN username TEXT UNIQUE,
    ADD COLUMN email TEXT UNIQUE,
    ADD COLUMN password_hash TEXT,
    ADD COLUMN wallet_backup TEXT;
