// Command worker runs the background cron services: the Hunger Service (hourly starvation
// checks), the Incubation Service (hourly egg-care checks), and the Ecosystem Task Service
// (periodic on-chain-activity verification for tasks like "hold ARB" or "active wallet"). The
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
	"time"

	"github.com/eggfarm/backend/internal/chain"
	"github.com/eggfarm/backend/internal/config"
	"github.com/eggfarm/backend/internal/db"
	"github.com/eggfarm/backend/internal/services/ecosystem"
	"github.com/eggfarm/backend/internal/services/hunger"
	"github.com/eggfarm/backend/internal/services/incubation"
	"github.com/eggfarm/backend/internal/services/task"
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
	ecosystemSvc := ecosystem.NewService(pool, chainClient, taskSvc)

	if cfg.ArbTokenAddress != "" {
		for _, taskID := range []string{"arb_token_holder", "arb_token_received"} {
			if err := ecosystemSvc.ConfigureContractAddress(ctx, taskID, cfg.ArbTokenAddress); err != nil {
				slog.Error("configuring ARB token task failed", "taskId", taskID, "error", err)
			}
		}
	} else {
		slog.Info("ARB_TOKEN_ADDRESS not set -- arb_token_holder/arb_token_received tasks stay inactive on this network")
	}

	hungerSvc := hunger.NewService(pool, chainClient, nil)
	incubationSvc := incubation.NewService(pool, chainClient, nil)

	go hungerSvc.Run(ctx, time.Hour)
	go incubationSvc.Run(ctx, time.Hour)
	go ecosystemSvc.RunBalanceChecks(ctx, 10*time.Minute)
	go ecosystemSvc.RunTokenReceivedChecks(ctx, 15*time.Second)
	go ecosystemSvc.RunContractEventChecks(ctx, 15*time.Second)
	go ecosystemSvc.RunNamedEventChecks(ctx, 15*time.Second)

	slog.Info("worker started", "services", "hunger, incubation, ecosystem")
	<-ctx.Done()
	slog.Info("worker shutting down")
}
