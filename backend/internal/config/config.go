// Package config loads process configuration from environment variables (and a local .env
// file in development).
package config

import (
	"fmt"
	"os"
	"strconv"

	"github.com/joho/godotenv"
)

type Config struct {
	Port               string
	DatabaseURL        string
	RedisURL           string
	RPCURL             string
	ChainID            int64
	FeedTokenAddress   string
	EggNFTAddress      string
	CreatureNFTAddress string
	MarketplaceAddress string
	// BattleEscrowAddress holds PvP wager stakes in native currency (ETH/ARB) -- see
	// internal/services/battle and contracts/src/BattleEscrow.sol. Optional; wagers are
	// unavailable (a clear error, not a crash) if unset.
	BattleEscrowAddress string
	BackendPrivateKey   string // signer for mintReward / server-authoritative layEgg calls, and BattleEscrow's RESOLVER_ROLE
	DeployBlock         uint64 // block the contracts were deployed at, indexer start point

	// ArbTokenAddress is the real ARB governance token contract, used to activate the
	// arb_token_holder/arb_token_received ecosystem tasks. Left empty on networks where ARB
	// isn't deployed (e.g. Arbitrum Sepolia, local Anvil) -- those tasks simply stay inactive.
	ArbTokenAddress string

	// TreasuryAddress is where the platform's own cut lands: the rake on PvP wagers, and
	// protocols' native-currency payments when they buy $FEED to fund a partner quest. Never the
	// backend signer's own address -- that wallet mints/burns on the game's behalf and shouldn't
	// also accumulate platform revenue.
	TreasuryAddress string

	// FeedPerNativeUnit is the $FEED-per-ARB(or ETH) exchange rate protocols get when buying
	// $FEED to fund a partner quest's reward pool (see internal/services/task.FundTask).
	FeedPerNativeUnit int64
}

func Load() (*Config, error) {
	_ = godotenv.Load() // ignore error: fine if no .env file is present (e.g. in prod)

	cfg := &Config{
		Port:                getEnv("PORT", "8080"),
		DatabaseURL:         getEnv("DATABASE_URL", "postgres://eggfarm:eggfarm@localhost:5432/eggfarm?sslmode=disable"),
		RedisURL:            getEnv("REDIS_URL", "redis://localhost:6379/0"),
		RPCURL:              getEnv("ARBITRUM_SEPOLIA_RPC_URL", "https://sepolia-rollup.arbitrum.io/rpc"),
		ChainID:             getEnvInt64("CHAIN_ID", 421614), // Arbitrum Sepolia by default; override for local Anvil (31337) etc.
		FeedTokenAddress:    os.Getenv("FEED_TOKEN_ADDRESS"),
		EggNFTAddress:       os.Getenv("EGG_NFT_ADDRESS"),
		CreatureNFTAddress:  os.Getenv("CREATURE_NFT_ADDRESS"),
		MarketplaceAddress:  os.Getenv("MARKETPLACE_ADDRESS"),
		BattleEscrowAddress: os.Getenv("BATTLE_ESCROW_ADDRESS"),
		BackendPrivateKey:   os.Getenv("BACKEND_SIGNER_PRIVATE_KEY"),
		DeployBlock:         uint64(getEnvInt64("DEPLOY_BLOCK", 0)),
		ArbTokenAddress:     os.Getenv("ARB_TOKEN_ADDRESS"),
		TreasuryAddress:     os.Getenv("TREASURY_ADDRESS"),
		FeedPerNativeUnit:   getEnvInt64("FEED_PER_NATIVE_UNIT", 100),
	}

	if cfg.FeedTokenAddress == "" || cfg.EggNFTAddress == "" || cfg.CreatureNFTAddress == "" || cfg.MarketplaceAddress == "" {
		return nil, fmt.Errorf("missing one or more required contract address env vars (FEED_TOKEN_ADDRESS, EGG_NFT_ADDRESS, CREATURE_NFT_ADDRESS, MARKETPLACE_ADDRESS)")
	}

	return cfg, nil
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func getEnvInt64(key string, fallback int64) int64 {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	parsed, err := strconv.ParseInt(v, 10, 64)
	if err != nil {
		return fallback
	}
	return parsed
}
