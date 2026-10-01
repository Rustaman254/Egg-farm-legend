// Package walletwatch is the "always check the user's wallet" background service: while a
// player has the app open (i.e. their websocket is connected to the realtime.Hub), it polls
// their native-token (ETH/ARB) balance on a short interval and, the moment it changes, pushes a
// wallet_event over the socket and logs it to wallet_events -- a battle payout landing, a
// marketplace sale clearing, or just gas spent, all show up without the player refreshing
// anything. Wallets that aren't currently connected are never polled: there's no socket to push
// to, and the REST /farm endpoint already reads the live balance on every load anyway.
package walletwatch

import (
	"context"
	"fmt"
	"log/slog"
	"math/big"
	"sync"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/jackc/pgx/v5/pgxpool"
)

// BalanceReader is satisfied by internal/chain.Client.
type BalanceReader interface {
	NativeBalance(ctx context.Context, wallet string) (*big.Int, error)
}

// Notifier is satisfied by internal/realtime.Hub.
type Notifier interface {
	Notify(wallet string, eventType string, payload any)
	ConnectedWallets() []string
}

type Service struct {
	db    *pgxpool.Pool
	chain BalanceReader
	hub   Notifier

	mu       sync.Mutex
	lastSeen map[string]*big.Int // lowercased wallet -> last known balance this process has observed
}

func NewService(db *pgxpool.Pool, chain BalanceReader, hub Notifier) *Service {
	return &Service{db: db, chain: chain, hub: hub, lastSeen: make(map[string]*big.Int)}
}

// Run polls every interval until ctx is cancelled.
func (s *Service) Run(ctx context.Context, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
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
	for _, wallet := range s.hub.ConnectedWallets() {
		balance, err := s.chain.NativeBalance(ctx, wallet)
		if err != nil {
			slog.Error("wallet watcher: reading native balance failed", "wallet", wallet, "error", err)
			continue
		}

		s.mu.Lock()
		previous, seenBefore := s.lastSeen[wallet]
		s.lastSeen[wallet] = balance
		s.mu.Unlock()

		// The first observation of a session has nothing to diff against -- just remember it.
		if !seenBefore || previous.Cmp(balance) == 0 {
			continue
		}

		delta := new(big.Int).Sub(balance, previous)
		s.recordChange(ctx, wallet, balance, delta)
	}
}

func (s *Service) recordChange(ctx context.Context, wallet string, newBalance, delta *big.Int) {
	up := delta.Sign() > 0
	kind := "balance_down"
	verb := "decreased"
	if up {
		kind = "balance_up"
		verb = "increased"
	}
	absDelta := new(big.Int).Abs(delta)
	message := fmt.Sprintf("Your wallet balance %s by %s ETH", verb, formatEtherApprox(absDelta))
	amountWei := absDelta.String()

	// players.wallet_address is stored EIP-55 checksummed (see gamestate/ecosystem's ensurePlayer
	// and the marketplace indexer) -- the hub only ever hands back lowercased wallet keys, so this
	// must re-checksum before the FK-constrained insert or it violates wallet_events_wallet_address_fkey.
	checksummed := common.HexToAddress(wallet).Hex()
	if _, err := s.db.Exec(ctx, `
		INSERT INTO wallet_events (wallet_address, kind, message, amount_wei) VALUES ($1, $2, $3, $4)`,
		checksummed, kind, message, amountWei); err != nil {
		slog.Error("wallet watcher: recording wallet event failed", "wallet", wallet, "error", err)
	}

	s.hub.Notify(wallet, "wallet_event", map[string]any{
		"kind":       kind,
		"message":    message,
		"amountWei":  amountWei,
		"balanceWei": newBalance.String(),
		"deltaWei":   delta.String(),
	})
}

// formatEtherApprox renders wei as an ETH string to 5 decimal places -- good enough for a
// notification message, not meant for on-chain-precision display (the frontend formats the exact
// wei value itself wherever precision matters).
func formatEtherApprox(wei *big.Int) string {
	f := new(big.Float).SetInt(wei)
	f.Quo(f, big.NewFloat(1e18))
	return f.Text('f', 5)
}
