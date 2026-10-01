// Command migrate applies migrations/*.sql to DATABASE_URL in filename order, recording each one
// in schema_migrations so re-runs are no-ops. Locally, docker-compose's Postgres already applies
// these through docker-entrypoint-initdb.d; this command is for hosted databases (it runs as the
// Render pre-deploy step, see render.yaml). Don't point it at a database docker-compose already
// initialised -- that one has no schema_migrations rows, so every file would be re-applied.
package main

import (
	"context"
	"flag"
	"log/slog"
	"os"
	"path/filepath"
	"sort"

	"github.com/eggfarm/backend/internal/config"
	"github.com/eggfarm/backend/internal/db"
	"github.com/jackc/pgx/v5"
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

	if _, err := pool.Exec(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (
		filename   TEXT PRIMARY KEY,
		applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
	)`); err != nil {
		slog.Error("creating schema_migrations failed", "error", err)
		os.Exit(1)
	}

	files, err := filepath.Glob(filepath.Join(*dir, "*.sql"))
	if err != nil || len(files) == 0 {
		slog.Error("no migration files found", "dir", *dir, "error", err)
		os.Exit(1)
	}
	sort.Strings(files)

	applied := 0
	for _, path := range files {
		name := filepath.Base(path)

		var exists bool
		if err := pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE filename = $1)`, name).Scan(&exists); err != nil {
			slog.Error("checking migration failed", "file", name, "error", err)
			os.Exit(1)
		}
		if exists {
			continue
		}

		sql, err := os.ReadFile(path)
		if err != nil {
			slog.Error("reading migration failed", "file", name, "error", err)
			os.Exit(1)
		}

		// One transaction per file, so a failing migration leaves neither its schema changes nor
		// its schema_migrations row behind. Exec with no arguments uses the simple query
		// protocol, which allows the multiple statements each file contains.
		err = pgx.BeginFunc(ctx, pool, func(tx pgx.Tx) error {
			if _, err := tx.Exec(ctx, string(sql)); err != nil {
				return err
			}
			_, err := tx.Exec(ctx, `INSERT INTO schema_migrations (filename) VALUES ($1)`, name)
			return err
		})
		if err != nil {
			slog.Error("applying migration failed", "file", name, "error", err)
			os.Exit(1)
		}
		slog.Info("applied migration", "file", name)
		applied++
	}

	slog.Info("migrations up to date", "applied", applied, "total", len(files))
}
