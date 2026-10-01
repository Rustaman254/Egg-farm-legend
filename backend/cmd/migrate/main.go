// Command migrate applies migrations/*.sql to DATABASE_URL once each -- see db.Migrate. The API
// server can do the same on startup with AUTO_MIGRATE=true (how the free Render setup in
// render.yaml runs it, since free instances have no pre-deploy step).
package main

import (
	"context"
	"flag"
	"log/slog"
	"os"

	"github.com/eggfarm/backend/internal/config"
	"github.com/eggfarm/backend/internal/db"
)

func main() {
	dir := flag.String("dir", "migrations", "directory containing the *.sql migration files")
	flag.Parse()

	ctx := context.Background()
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

	if err := db.Migrate(ctx, pool, *dir); err != nil {
		slog.Error("migrating failed", "error", err)
		os.Exit(1)
	}
}
