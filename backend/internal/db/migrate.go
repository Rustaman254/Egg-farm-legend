package db

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"sort"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Migrate applies dir/*.sql in filename order, recording each file in schema_migrations so
// re-runs are no-ops. Each file runs in its own transaction, so a failing migration leaves
// neither its schema changes nor its schema_migrations row behind.
//
// Locally, docker-compose's Postgres already applies these through docker-entrypoint-initdb.d
// and has no schema_migrations rows -- don't run this against that database, or every file
// would be re-applied.
func Migrate(ctx context.Context, pool *pgxpool.Pool, dir string) error {
	if _, err := pool.Exec(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (
		filename   TEXT PRIMARY KEY,
		applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
	)`); err != nil {
		return fmt.Errorf("creating schema_migrations: %w", err)
	}

	files, err := filepath.Glob(filepath.Join(dir, "*.sql"))
	if err != nil {
		return fmt.Errorf("listing migrations: %w", err)
	}
	if len(files) == 0 {
		return fmt.Errorf("no migration files found in %q", dir)
	}
	sort.Strings(files)

	applied := 0
	for _, path := range files {
		name := filepath.Base(path)

		var exists bool
		if err := pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE filename = $1)`, name).Scan(&exists); err != nil {
			return fmt.Errorf("checking migration %s: %w", name, err)
		}
		if exists {
			continue
		}

		sql, err := os.ReadFile(path)
		if err != nil {
			return fmt.Errorf("reading migration %s: %w", name, err)
		}

		// Exec with no arguments uses the simple query protocol, which allows the multiple
		// statements each file contains.
		err = pgx.BeginFunc(ctx, pool, func(tx pgx.Tx) error {
			if _, err := tx.Exec(ctx, string(sql)); err != nil {
				return err
			}
			_, err := tx.Exec(ctx, `INSERT INTO schema_migrations (filename) VALUES ($1)`, name)
			return err
		})
		if err != nil {
			return fmt.Errorf("applying migration %s: %w", name, err)
		}
		slog.Info("applied migration", "file", name)
		applied++
	}

	slog.Info("migrations up to date", "applied", applied, "total", len(files))
	return nil
}
