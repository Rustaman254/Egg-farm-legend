// Command server runs the REST API and the Marketplace Indexer. It's the process the Flutter
// app talks to. Run `cmd/worker` alongside it for the background services, or set RUN_WORKER=true
// to run them in this process instead.
package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/eggfarm/backend/internal/api"
	"github.com/eggfarm/backend/internal/chain"
	"github.com/eggfarm/backend/internal/config"
	"github.com/eggfarm/backend/internal/db"
	"github.com/eggfarm/backend/internal/realtime"
	"github.com/eggfarm/backend/internal/services/auth"
	"github.com/eggfarm/backend/internal/services/battle"
	"github.com/eggfarm/backend/internal/services/gamestate"
	"github.com/eggfarm/backend/internal/services/marketplace"
	"github.com/eggfarm/backend/internal/services/shop"
	"github.com/eggfarm/backend/internal/services/task"
	"github.com/eggfarm/backend/internal/services/walletwatch"
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

	if cfg.AutoMigrate {
		if err := db.Migrate(ctx, pool, "migrations"); err != nil {
			slog.Error("migrating failed", "error", err)
			os.Exit(1)
		}
	}

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
	arenaHub := realtime.NewHub()
	battleSvc := battle.NewService(pool, chainClient, taskSvc, arenaHub, cfg.TreasuryAddress, chainClient)
	shopSvc := shop.NewService(pool, chainClient, chainClient, cfg.TreasuryAddress)
	authSvc := auth.NewService(pool)

	marketplaceIndexer := marketplace.NewIndexer(pool, chainClient, taskSvc, arenaHub, cfg.DeployBlock, cfg.EggNFTAddress, cfg.CreatureNFTAddress)
	go marketplaceIndexer.Run(ctx, 15*time.Second)

	gameStateIndexer := gamestate.NewIndexer(pool, chainClient, taskSvc, cfg.DeployBlock, cfg.CreatureNFTAddress, cfg.EggNFTAddress)
	go gameStateIndexer.Run(ctx, 15*time.Second)

	if cfg.RunWorker {
		worker.Start(ctx, cfg, pool, chainClient, taskSvc)
	}

	walletWatcher := walletwatch.NewService(pool, chainClient, arenaHub)
	go walletWatcher.Run(ctx, 10*time.Second)

	router := api.NewRouter(pool, taskSvc, battleSvc, chainClient, arenaHub, shopSvc, authSvc)
	httpServer := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           router,
		ReadHeaderTimeout: 5 * time.Second,
	}

	go func() {
		slog.Info("api server listening", "port", cfg.Port)
		if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("api server failed", "error", err)
			os.Exit(1)
		}
	}()

	<-ctx.Done()
	slog.Info("shutting down")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = httpServer.Shutdown(shutdownCtx)
}
