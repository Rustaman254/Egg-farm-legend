// Command worker runs the background cron services (see internal/worker) as their own process.
// Set RUN_WORKER=true on cmd/server instead to run them inside the API process. The
// daily task-reset boundary is implicit: task_progress rows are keyed by UTC date, so "reset"
// just means the previous day's rows stop being read -- no active reset job is needed, see
// internal/services/task.
package main

import (
	"context"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"github.com/eggfarm/backend/internal/chain"
	"github.com/eggfarm/backend/internal/config"
	"github.com/eggfarm/backend/internal/db"
	"github.com/eggfarm/backend/internal/services/task"
	"github.com/eggfarm/backend/internal/worker"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	cfg, err := config.Load()
	if err != nil {
		slog.Error("loading config failed", "error", err)
		os.Exit(1)
	}

	pool, err := db.NewPostgres(ctx, cfg.DatabaseURL)
	if err != nil {
		slog.Error("connecting to postgres failed", "error", err)
		os.Exit(1)
	}
	defer pool.Close()

	chainClient, err := chain.New(ctx, chain.Config{
		RPCURL:              cfg.RPCURL,
		ChainID:             cfg.ChainID,
		FeedTokenAddress:    cfg.FeedTokenAddress,
		EggNFTAddress:       cfg.EggNFTAddress,
		CreatureNFTAddress:  cfg.CreatureNFTAddress,
		MarketplaceAddress:  cfg.MarketplaceAddress,
		BattleEscrowAddress: cfg.BattleEscrowAddress,
		SignerPrivateKey:    cfg.BackendPrivateKey,
	})
	if err != nil {
		slog.Error("creating chain client failed", "error", err)
		os.Exit(1)
	}

	taskSvc := task.NewService(pool, chainClient, chainClient, chainClient, cfg.TreasuryAddress, cfg.FeedPerNativeUnit)
	worker.Start(ctx, cfg, pool, chainClient, taskSvc)

	<-ctx.Done()
	slog.Info("worker shutting down")
}
