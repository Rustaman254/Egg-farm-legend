// Package worker starts the background cron services: the Hunger Service (hourly starvation
// checks), the Incubation Service (hourly egg-care checks), and the Ecosystem Task Service
// (periodic on-chain-activity verification for tasks like "hold ARB" or "active wallet"). It
// runs either as its own process (cmd/worker) or inside the API process when RUN_WORKER=true
// (cmd/server), for hosts with a single free instance and no separate background workers.
package worker

import (
	"context"
	"log/slog"
	"time"

	"github.com/eggfarm/backend/internal/chain"
	"github.com/eggfarm/backend/internal/config"
	"github.com/eggfarm/backend/internal/services/ecosystem"
	"github.com/eggfarm/backend/internal/services/hunger"
	"github.com/eggfarm/backend/internal/services/incubation"
	"github.com/eggfarm/backend/internal/services/task"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Start launches every background loop as a goroutine and returns immediately; the loops stop
// when ctx is cancelled.
func Start(ctx context.Context, cfg *config.Config, pool *pgxpool.Pool, chainClient *chain.Client, taskSvc *task.Service) {
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
}
