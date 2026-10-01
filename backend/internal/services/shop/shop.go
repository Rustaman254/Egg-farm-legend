// Package shop implements the $FEED Shop: pre-made "bag of feed" packages, priced in native
// currency (ARB/ETH) and paid straight to the platform treasury -- the third platform revenue
// stream alongside the PvP wager rake and partner-quest funding (see internal/services/battle and
// internal/services/task). A purchase mints the package's $FEED straight to the buyer; there's no
// escrow or pool involved, unlike a quest's funded_feed.
package shop

import (
	"context"
	"errors"
	"fmt"
	"math/big"

	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrPackageNotFound    = errors.New("feed package not found")
	ErrPaymentUnverified  = errors.New("couldn't verify that payment on-chain")
	ErrPaymentTooLow      = errors.New("payment doesn't cover this package's price")
	ErrPaymentAlreadyUsed = errors.New("that payment has already been credited")
)

// Package is a pre-made feed bag -- "kg" is flavor (a bag of chicken feed, not a literal unit the
// contracts track) mapped onto a fixed whole-$FEED amount. Larger bags carry a bulk discount
// (more $FEED per native-currency unit spent) to make buying in bulk actually worth it.
type Package struct {
	ID        string `json:"id"`
	KG        int    `json:"kg"`
	FeedWhole int64  `json:"feedWhole"`
	PriceWei  string `json:"priceWei"`
}

// Packages is the fixed catalog. Price scales sub-linearly with kg (a bigger bag is a better
// per-kg deal): 1kg ~ 0.01 ARB/10 FEED, 5kg ~ 0.045 ARB/55 FEED (10% bonus), 20kg ~ 0.16 ARB/240
// FEED (20% bonus).
var Packages = []Package{
	{ID: "1kg", KG: 1, FeedWhole: 10, PriceWei: "10000000000000000"},
	{ID: "5kg", KG: 5, FeedWhole: 55, PriceWei: "45000000000000000"},
	{ID: "20kg", KG: 20, FeedWhole: 240, PriceWei: "160000000000000000"},
}

func findPackage(id string) (Package, bool) {
	for _, p := range Packages {
		if p.ID == id {
			return p, true
		}
	}
	return Package{}, false
}

// FeedMinter is satisfied by internal/chain.Client.
type FeedMinter interface {
	MintReward(ctx context.Context, to string, amount *big.Int) (txHash string, err error)
}

// PaymentVerifier is satisfied by internal/chain.Client.
type PaymentVerifier interface {
	VerifyNativePayment(ctx context.Context, txHash, to string) (*big.Int, error)
}

type Service struct {
	db       *pgxpool.Pool
	minter   FeedMinter
	payments PaymentVerifier
	treasury string
}

func NewService(db *pgxpool.Pool, minter FeedMinter, payments PaymentVerifier, treasury string) *Service {
	return &Service{db: db, minter: minter, payments: payments, treasury: treasury}
}

// Purchase verifies the buyer's payment landed on the treasury and covers the package's price,
// then mints the package's $FEED to them. txHash can only ever be credited once.
func (s *Service) Purchase(ctx context.Context, buyer, packageID, txHash string) (feedCredited *big.Int, err error) {
	pkg, ok := findPackage(packageID)
	if !ok {
		return nil, ErrPackageNotFound
	}
	if s.treasury == "" {
		return nil, fmt.Errorf("no treasury address configured")
	}

	paidWei, err := s.payments.VerifyNativePayment(ctx, txHash, s.treasury)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrPaymentUnverified, err)
	}
	price, ok := new(big.Int).SetString(pkg.PriceWei, 10)
	if !ok {
		return nil, fmt.Errorf("invalid package price %q", pkg.PriceWei)
	}
	if paidWei.Cmp(price) < 0 {
		return nil, ErrPaymentTooLow
	}

	feedCredited = new(big.Int).Mul(big.NewInt(pkg.FeedWhole), big.NewInt(1e18))

	tag, err := s.db.Exec(ctx, `
		INSERT INTO platform_revenue (source, wallet_address, tx_hash, native_amount_wei, feed_amount)
		VALUES ('feed_shop', $1, $2, $3, $4)
		ON CONFLICT (tx_hash) WHERE tx_hash IS NOT NULL DO NOTHING`,
		buyer, txHash, paidWei.String(), feedCredited.String())
	if err != nil {
		return nil, fmt.Errorf("recording feed shop purchase: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return nil, ErrPaymentAlreadyUsed
	}

	if _, err := s.minter.MintReward(ctx, buyer, feedCredited); err != nil {
		return nil, fmt.Errorf("minting purchased feed: %w", err)
	}
	return feedCredited, nil
}
