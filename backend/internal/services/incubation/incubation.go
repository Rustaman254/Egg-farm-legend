// Package incubation implements the Incubation Service: once an hour it walks every unhatched
// egg, calls the on-chain checkEggCare(tokenId) (which lazily applies the rarity-scaled care
// decay and spoils the egg if care has been at 0 for >= 12h), and syncs the result back into
// Postgres. Mirrors internal/services/hunger's pattern exactly, just for eggs instead of
// creatures.
package incubation

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// CareChecker is satisfied by internal/chain.Client.
type CareChecker interface {
	CheckEggCare(ctx context.Context, tokenID int64) (txHash string, err error)
	GetCareLevel(ctx context.Context, tokenID int64) (uint8, error)
	IsEggRotten(ctx context.Context, tokenID int64) (bool, error)
}

// Notifier abstracts push delivery -- see hunger.Notifier for the same pattern.
type Notifier interface {
	NotifyNeglected(ctx context.Context, wallet string, tokenID int64, careLevel uint8) error
}

type LogNotifier struct{}

func (LogNotifier) NotifyNeglected(_ context.Context, wallet string, tokenID int64, careLevel uint8) error {
	slog.Info("push: egg needs care", "wallet", wallet, "tokenId", tokenID, "careLevel", careLevel)
	return nil
}

const neglectedPushThreshold = 30 // send a push once care drops below this

type Service struct {
	db       *pgxpool.Pool
	chain    CareChecker
	notifier Notifier
}

func NewService(db *pgxpool.Pool, chain CareChecker, notifier Notifier) *Service {
	if notifier == nil {
		notifier = LogNotifier{}
	}
	return &Service{db: db, chain: chain, notifier: notifier}
}

// Run blocks, ticking every interval until ctx is cancelled. Call it from a goroutine.
func (s *Service) Run(ctx context.Context, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	s.tick(ctx)
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.tick(ctx)
		}
	}
}

func (s *Service) tick(ctx context.Context) {
	tokenIDs, err := s.unhatchedEggIDs(ctx)
	if err != nil {
		slog.Error("incubation service: listing unhatched eggs failed", "error", err)
		return
	}

	slog.Info("incubation service tick", "eggCount", len(tokenIDs))
	for _, tokenID := range tokenIDs {
		if err := s.checkOne(ctx, tokenID); err != nil {
			slog.Error("incubation service: check failed", "tokenId", tokenID, "error", err)
		}
	}
}

func (s *Service) checkOne(ctx context.Context, tokenID int64) error {
	if _, err := s.chain.CheckEggCare(ctx, tokenID); err != nil {
		return fmt.Errorf("checkEggCare: %w", err)
	}

	rotten, err := s.chain.IsEggRotten(ctx, tokenID)
	if err != nil {
		return fmt.Errorf("isEggRotten: %w", err)
	}

	var owner string
	if err := s.db.QueryRow(ctx, `SELECT owner_address FROM eggs WHERE token_id = $1`, tokenID).Scan(&owner); err != nil {
		return fmt.Errorf("looking up owner: %w", err)
	}

	if rotten {
		_, err := s.db.Exec(ctx, `UPDATE eggs SET is_rotten = true WHERE token_id = $1`, tokenID)
		return err
	}

	care, err := s.chain.GetCareLevel(ctx, tokenID)
	if err != nil {
		return fmt.Errorf("getCareLevel: %w", err)
	}

	if _, err := s.db.Exec(ctx, `UPDATE eggs SET care_level = $2 WHERE token_id = $1`, tokenID, care); err != nil {
		return err
	}

	if care < neglectedPushThreshold {
		if err := s.notifier.NotifyNeglected(ctx, owner, tokenID, care); err != nil {
			slog.Warn("incubation service: push notification failed", "tokenId", tokenID, "error", err)
		}
	}

	return nil
}

func (s *Service) unhatchedEggIDs(ctx context.Context) ([]int64, error) {
	rows, err := s.db.Query(ctx, `SELECT token_id FROM eggs WHERE NOT is_hatched AND NOT is_rotten`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ids []int64
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}
