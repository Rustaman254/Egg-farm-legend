// Package hunger implements the Hunger Service: once an hour it walks every live creature,
// calls the on-chain checkStarvation(tokenId) (which lazily applies the 10%/hour decay and
// burns the NFT if hunger has been 0 for >= 24h), syncs the result back into Postgres, and
// queues a "your creature is hungry" push notification when hunger drops low.
package hunger

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// StarvationChecker is satisfied by internal/chain.Client.
type StarvationChecker interface {
	CheckStarvation(ctx context.Context, tokenID int64) (txHash string, err error)
	GetHunger(ctx context.Context, tokenID int64) (uint8, error)
	IsAlive(ctx context.Context, tokenID int64) (bool, error)
}

// Notifier abstracts push delivery so this package doesn't depend on a specific provider (FCM,
// APNs, etc.) -- swap in a real implementation without touching the tick logic.
type Notifier interface {
	NotifyHungry(ctx context.Context, wallet string, tokenID int64, hunger uint8) error
}

type LogNotifier struct{}

func (LogNotifier) NotifyHungry(_ context.Context, wallet string, tokenID int64, hunger uint8) error {
	slog.Info("push: creature is hungry", "wallet", wallet, "tokenId", tokenID, "hunger", hunger)
	return nil
}

const hungryPushThreshold = 30 // send a push once hunger drops below this

// neglectPenaltyAmount: a creature left at 0 hunger for 6+ hours (see applyNeglectPenalty's SQL)
// takes a permanent care_score hit -- real stakes for neglect short of outright starving (24h,
// on-chain, burns the NFT entirely). One penalty per neglect episode (see neglect_penalized), so
// leaving a creature neglected for days doesn't repeatedly grind its level down every hour.
const neglectPenaltyAmount = 10

type Service struct {
	db       *pgxpool.Pool
	chain    StarvationChecker
	notifier Notifier
}

func NewService(db *pgxpool.Pool, chain StarvationChecker, notifier Notifier) *Service {
	if notifier == nil {
		notifier = LogNotifier{}
	}
	return &Service{db: db, chain: chain, notifier: notifier}
}

// Run blocks, ticking every interval until ctx is cancelled. Call it from a goroutine.
func (s *Service) Run(ctx context.Context, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	s.tick(ctx) // run once immediately on startup rather than waiting a full interval
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
	tokenIDs, err := s.liveCreatureIDs(ctx)
	if err != nil {
		slog.Error("hunger service: listing live creatures failed", "error", err)
		return
	}

	slog.Info("hunger service tick", "creatureCount", len(tokenIDs))
	for _, tokenID := range tokenIDs {
		if err := s.checkOne(ctx, tokenID); err != nil {
			slog.Error("hunger service: check failed", "tokenId", tokenID, "error", err)
		}
	}
}

func (s *Service) checkOne(ctx context.Context, tokenID int64) error {
	if _, err := s.chain.CheckStarvation(ctx, tokenID); err != nil {
		return fmt.Errorf("checkStarvation: %w", err)
	}

	alive, err := s.chain.IsAlive(ctx, tokenID)
	if err != nil {
		return fmt.Errorf("isAlive: %w", err)
	}
	if !alive {
		_, err := s.db.Exec(ctx, `UPDATE creatures SET is_dead = true, updated_at = now() WHERE token_id = $1`, tokenID)
		return err
	}

	hunger, err := s.chain.GetHunger(ctx, tokenID)
	if err != nil {
		return fmt.Errorf("getHunger: %w", err)
	}

	var owner string
	if err := s.db.QueryRow(ctx, `SELECT owner_address FROM creatures WHERE token_id = $1`, tokenID).Scan(&owner); err != nil {
		return fmt.Errorf("looking up owner: %w", err)
	}

	if hunger < hungryPushThreshold {
		if err := s.notifier.NotifyHungry(ctx, owner, tokenID, hunger); err != nil {
			slog.Warn("hunger service: push notification failed", "tokenId", tokenID, "error", err)
		}
	}

	return s.applyNeglectPenalty(ctx, tokenID)
}

// applyNeglectPenalty docks care_score once a creature has sat at 0 hunger past
// neglectPenaltyAfter -- deterioration from neglect, distinct from (and well before) the 24h
// starve-to-death threshold the contract itself enforces.
func (s *Service) applyNeglectPenalty(ctx context.Context, tokenID int64) error {
	tag, err := s.db.Exec(ctx, `
		UPDATE creatures
		SET care_score = GREATEST(0, care_score - $2), neglect_penalized = true, updated_at = now()
		WHERE token_id = $1
		  AND hunger_zero_since IS NOT NULL
		  AND hunger_zero_since <= now() - interval '6 hours'
		  AND NOT neglect_penalized`,
		tokenID, neglectPenaltyAmount)
	if err != nil {
		return fmt.Errorf("applying neglect penalty: %w", err)
	}
	if tag.RowsAffected() > 0 {
		slog.Info("hunger service: applied neglect penalty", "tokenId", tokenID, "careScorePenalty", neglectPenaltyAmount)
	}
	return nil
}

func (s *Service) liveCreatureIDs(ctx context.Context) ([]int64, error) {
	rows, err := s.db.Query(ctx, `SELECT token_id FROM creatures WHERE NOT is_dead`)
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
