// Package chain wraps go-ethereum so the rest of the backend can call and listen to the
// EggFarm Legends contracts without depending on generated (abigen) bindings -- ABIs are
// embedded from the Foundry build output and bound at runtime via bind.BoundContract.
package chain

import (
	"context"
	_ "embed"
	"fmt"
	"math/big"
	"strings"
	"time"

	ethereum "github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
)

//go:embed abi/FeedToken.json
var feedTokenABIJSON []byte

//go:embed abi/EggNFT.json
var eggNFTABIJSON []byte

//go:embed abi/CreatureNFT.json
var creatureNFTABIJSON []byte

//go:embed abi/Marketplace.json
var marketplaceABIJSON []byte

//go:embed abi/ERC20.json
var erc20ABIJSON []byte

//go:embed abi/BattleEscrow.json
var battleEscrowABIJSON []byte

type Client struct {
	eth *ethclient.Client

	feedToken    *bind.BoundContract
	eggNFT       *bind.BoundContract
	creatureNFT  *bind.BoundContract
	marketplace  *bind.BoundContract
	battleEscrow *bind.BoundContract // nil if BattleEscrowAddress wasn't configured

	FeedTokenAddress    common.Address
	EggNFTAddress       common.Address
	CreatureNFTAddress  common.Address
	MarketplaceAddress  common.Address
	BattleEscrowAddress common.Address

	auth    *bind.TransactOpts
	chainID *big.Int
}

type Config struct {
	RPCURL              string
	ChainID             int64
	FeedTokenAddress    string
	EggNFTAddress       string
	CreatureNFTAddress  string
	MarketplaceAddress  string
	BattleEscrowAddress string // optional; wager escrow calls fail clearly if unset
	SignerPrivateKey    string // hex-encoded, no 0x prefix required
}

func New(ctx context.Context, cfg Config) (*Client, error) {
	ethClient, err := ethclient.DialContext(ctx, cfg.RPCURL)
	if err != nil {
		return nil, fmt.Errorf("dialing RPC %s: %w", cfg.RPCURL, err)
	}

	feedTokenABI, err := parseABI(feedTokenABIJSON)
	if err != nil {
		return nil, fmt.Errorf("parsing FeedToken ABI: %w", err)
	}
	eggNFTABI, err := parseABI(eggNFTABIJSON)
	if err != nil {
		return nil, fmt.Errorf("parsing EggNFT ABI: %w", err)
	}
	creatureNFTABI, err := parseABI(creatureNFTABIJSON)
	if err != nil {
		return nil, fmt.Errorf("parsing CreatureNFT ABI: %w", err)
	}
	marketplaceABI, err := parseABI(marketplaceABIJSON)
	if err != nil {
		return nil, fmt.Errorf("parsing Marketplace ABI: %w", err)
	}
	battleEscrowABI, err := parseABI(battleEscrowABIJSON)
	if err != nil {
		return nil, fmt.Errorf("parsing BattleEscrow ABI: %w", err)
	}

	feedTokenAddr := common.HexToAddress(cfg.FeedTokenAddress)
	eggNFTAddr := common.HexToAddress(cfg.EggNFTAddress)
	creatureNFTAddr := common.HexToAddress(cfg.CreatureNFTAddress)
	marketplaceAddr := common.HexToAddress(cfg.MarketplaceAddress)

	c := &Client{
		eth:                ethClient,
		feedToken:          bind.NewBoundContract(feedTokenAddr, feedTokenABI, ethClient, ethClient, ethClient),
		eggNFT:             bind.NewBoundContract(eggNFTAddr, eggNFTABI, ethClient, ethClient, ethClient),
		creatureNFT:        bind.NewBoundContract(creatureNFTAddr, creatureNFTABI, ethClient, ethClient, ethClient),
		marketplace:        bind.NewBoundContract(marketplaceAddr, marketplaceABI, ethClient, ethClient, ethClient),
		FeedTokenAddress:   feedTokenAddr,
		EggNFTAddress:      eggNFTAddr,
		CreatureNFTAddress: creatureNFTAddr,
		MarketplaceAddress: marketplaceAddr,
		chainID:            big.NewInt(cfg.ChainID),
	}

	if cfg.BattleEscrowAddress != "" {
		battleEscrowAddr := common.HexToAddress(cfg.BattleEscrowAddress)
		c.battleEscrow = bind.NewBoundContract(battleEscrowAddr, battleEscrowABI, ethClient, ethClient, ethClient)
		c.BattleEscrowAddress = battleEscrowAddr
	}

	if cfg.SignerPrivateKey != "" {
		key, err := crypto.HexToECDSA(strings.TrimPrefix(cfg.SignerPrivateKey, "0x"))
		if err != nil {
			return nil, fmt.Errorf("parsing backend signer private key: %w", err)
		}
		auth, err := bind.NewKeyedTransactorWithChainID(key, c.chainID)
		if err != nil {
			return nil, fmt.Errorf("creating transactor: %w", err)
		}
		c.auth = auth
	}

	return c, nil
}

func parseABI(raw []byte) (abi.ABI, error) {
	return abi.JSON(strings.NewReader(string(raw)))
}

func (c *Client) EthClient() *ethclient.Client { return c.eth }

// MintReward calls FeedToken.mintReward(to, amount). Satisfies task.FeedMinter.
func (c *Client) MintReward(ctx context.Context, to string, amount *big.Int) (string, error) {
	if c.auth == nil {
		return "", fmt.Errorf("chain client has no signer configured (BACKEND_SIGNER_PRIVATE_KEY unset)")
	}
	opts := c.txOpts(ctx)
	tx, err := c.feedToken.Transact(opts, "mintReward", common.HexToAddress(to), amount)
	if err != nil {
		return "", fmt.Errorf("mintReward tx: %w", err)
	}
	return tx.Hash().Hex(), nil
}

// BurnFeed calls FeedToken.burnFeed(from, amount) as the backend signer. Requires the signer to
// hold BURNER_ROLE on FeedToken (granted separately, on-chain, by an admin -- not something this
// client can do for itself). Used to take a player's wager off the board before it's re-minted to
// the winner in a PvP duel.
func (c *Client) BurnFeed(ctx context.Context, from string, amount *big.Int) (string, error) {
	if c.auth == nil {
		return "", fmt.Errorf("chain client has no signer configured (BACKEND_SIGNER_PRIVATE_KEY unset)")
	}
	opts := c.txOpts(ctx)
	tx, err := c.feedToken.Transact(opts, "burnFeed", common.HexToAddress(from), amount)
	if err != nil {
		return "", fmt.Errorf("burnFeed tx: %w", err)
	}
	return tx.Hash().Hex(), nil
}

// LayEgg calls EggNFT.layEgg(...) as the backend's GAME_CONTROLLER_ROLE signer -- the
// server-authoritative egg-laying path used for analytics / anti-cheat cross-checks or any flow
// where the backend, not the player, must be the one to mint (e.g. a sponsored/gasless tx).
func (c *Client) LayEgg(ctx context.Context, to string, rarity, species uint8, hatchTime uint64, parent1, parent2 uint64, isRotten bool) (string, error) {
	if c.auth == nil {
		return "", fmt.Errorf("chain client has no signer configured")
	}
	opts := c.txOpts(ctx)
	tx, err := c.eggNFT.Transact(opts, "layEgg",
		common.HexToAddress(to), rarity, species, hatchTime,
		new(big.Int).SetUint64(parent1), new(big.Int).SetUint64(parent2), isRotten)
	if err != nil {
		return "", fmt.Errorf("layEgg tx: %w", err)
	}
	return tx.Hash().Hex(), nil
}

// CheckStarvation calls CreatureNFT.checkStarvation(tokenId). Called by the Hunger Service cron
// for every live creature once an hour; anyone may call it, so the backend sponsors the gas.
func (c *Client) CheckStarvation(ctx context.Context, tokenID int64) (string, error) {
	if c.auth == nil {
		return "", fmt.Errorf("chain client has no signer configured")
	}
	opts := c.txOpts(ctx)
	tx, err := c.creatureNFT.Transact(opts, "checkStarvation", big.NewInt(tokenID))
	if err != nil {
		return "", fmt.Errorf("checkStarvation tx: %w", err)
	}
	return tx.Hash().Hex(), nil
}

// CheckEggCare calls EggNFT.checkEggCare(tokenId). Called by the Incubation Service cron for
// every unhatched egg; anyone may call it, so the backend sponsors the gas.
func (c *Client) CheckEggCare(ctx context.Context, tokenID int64) (string, error) {
	if c.auth == nil {
		return "", fmt.Errorf("chain client has no signer configured")
	}
	opts := c.txOpts(ctx)
	tx, err := c.eggNFT.Transact(opts, "checkEggCare", big.NewInt(tokenID))
	if err != nil {
		return "", fmt.Errorf("checkEggCare tx: %w", err)
	}
	return tx.Hash().Hex(), nil
}

// GetCareLevel reads EggNFT.getCareLevel(tokenId) (a view call, no gas or signer needed).
func (c *Client) GetCareLevel(ctx context.Context, tokenID int64) (uint8, error) {
	var out []interface{}
	err := c.eggNFT.Call(&bind.CallOpts{Context: ctx}, &out, "getCareLevel", big.NewInt(tokenID))
	if err != nil {
		return 0, fmt.Errorf("getCareLevel call: %w", err)
	}
	return out[0].(uint8), nil
}

// IsEggRotten reads EggNFT.isEggRotten(tokenId).
func (c *Client) IsEggRotten(ctx context.Context, tokenID int64) (bool, error) {
	var out []interface{}
	err := c.eggNFT.Call(&bind.CallOpts{Context: ctx}, &out, "isEggRotten", big.NewInt(tokenID))
	if err != nil {
		return false, fmt.Errorf("isEggRotten call: %w", err)
	}
	return out[0].(bool), nil
}

// GetFeedBalance reads FeedToken.balanceOf(wallet) live from chain. The API serves this
// directly rather than caching it in Postgres: $FEED balance changes on every feed/breed/task
// claim, and a cached column nothing ever wrote back to (see players.feed_balance_cached) is
// exactly how a player ends up staring at a balance of 0 after a reward actually minted.
func (c *Client) GetFeedBalance(ctx context.Context, wallet string) (*big.Int, error) {
	var out []interface{}
	err := c.feedToken.Call(&bind.CallOpts{Context: ctx}, &out, "balanceOf", common.HexToAddress(wallet))
	if err != nil {
		return nil, fmt.Errorf("balanceOf call: %w", err)
	}
	return out[0].(*big.Int), nil
}

// GetHunger reads CreatureNFT.getHunger(tokenId) (a pure/view call, no gas or signer needed).
func (c *Client) GetHunger(ctx context.Context, tokenID int64) (uint8, error) {
	var out []interface{}
	err := c.creatureNFT.Call(&bind.CallOpts{Context: ctx}, &out, "getHunger", big.NewInt(tokenID))
	if err != nil {
		return 0, fmt.Errorf("getHunger call: %w", err)
	}
	return out[0].(uint8), nil
}

// IsAlive reads CreatureNFT.isAlive(tokenId).
func (c *Client) IsAlive(ctx context.Context, tokenID int64) (bool, error) {
	var out []interface{}
	err := c.creatureNFT.Call(&bind.CallOpts{Context: ctx}, &out, "isAlive", big.NewInt(tokenID))
	if err != nil {
		return false, fmt.Errorf("isAlive call: %w", err)
	}
	return out[0].(bool), nil
}

// NativeBalance reads a wallet's native token balance (ETH on Arbitrum) directly from the node
// -- no contract involved. Backs the "Arbitrum Holder" ecosystem task.
func (c *Client) NativeBalance(ctx context.Context, wallet string) (*big.Int, error) {
	return c.eth.BalanceAt(ctx, common.HexToAddress(wallet), nil)
}

// TxCount reads a wallet's transaction count (nonce) -- a simple, reliable proxy for "has this
// wallet actually transacted on Arbitrum". Backs the "Active on Arbitrum" ecosystem task.
func (c *Client) TxCount(ctx context.Context, wallet string) (uint64, error) {
	return c.eth.NonceAt(ctx, common.HexToAddress(wallet), nil)
}

// VerifyNativePayment confirms a mined transaction actually paid `to` at least some amount of
// native currency (ETH/ARB), and returns exactly how much. Used to check a protocol's "buy $FEED
// to fund a task" payment before crediting anything -- reading the chain directly rather than
// trusting a client-supplied amount, the same way an on-chain purchase would be verified.
func (c *Client) VerifyNativePayment(ctx context.Context, txHash, to string) (*big.Int, error) {
	hash := common.HexToHash(txHash)
	tx, isPending, err := c.eth.TransactionByHash(ctx, hash)
	if err != nil {
		return nil, fmt.Errorf("looking up transaction: %w", err)
	}
	if isPending {
		return nil, fmt.Errorf("transaction not yet mined")
	}
	receipt, err := c.eth.TransactionReceipt(ctx, hash)
	if err != nil {
		return nil, fmt.Errorf("fetching receipt: %w", err)
	}
	if receipt.Status != types.ReceiptStatusSuccessful {
		return nil, fmt.Errorf("transaction reverted")
	}
	txTo := tx.To()
	if txTo == nil || !strings.EqualFold(txTo.Hex(), to) {
		return nil, fmt.Errorf("transaction did not pay the expected address")
	}
	return tx.Value(), nil
}

// TokenBalance reads balanceOf(wallet) on an arbitrary ERC-20 contract -- e.g. the ARB
// governance token -- using a minimal standard ABI rather than one bound at construction time,
// since which token to check is configured per ecosystem task, not fixed at startup.
func (c *Client) TokenBalance(ctx context.Context, tokenAddress, wallet string) (*big.Int, error) {
	erc20ABI, err := parseABI(erc20ABIJSON)
	if err != nil {
		return nil, fmt.Errorf("parsing ERC20 ABI: %w", err)
	}
	bound := bind.NewBoundContract(common.HexToAddress(tokenAddress), erc20ABI, c.eth, c.eth, c.eth)
	var out []interface{}
	if err := bound.Call(&bind.CallOpts{Context: ctx}, &out, "balanceOf", common.HexToAddress(wallet)); err != nil {
		return nil, fmt.Errorf("balanceOf call: %w", err)
	}
	return out[0].(*big.Int), nil
}

// ERC20ABI exposes the parsed standard ABI so the ecosystem indexer can decode Transfer events
// from any ERC-20 contract, regardless of which token address emitted them.
func (c *Client) ERC20ABI() abi.ABI {
	a, _ := parseABI(erc20ABIJSON)
	return a
}

// FilterMarketplaceLogs fetches raw Marketplace contract logs (Listed/Sold/Cancelled) in
// [fromBlock, toBlock] for the indexer to decode and persist.
func (c *Client) FilterMarketplaceLogs(ctx context.Context, fromBlock, toBlock uint64) ([]types.Log, error) {
	return c.FilterLogs(ctx, []common.Address{c.MarketplaceAddress}, fromBlock, toBlock)
}

// FilterLogs fetches raw logs emitted by any of `addresses` in [fromBlock, toBlock]. Used by the
// game-state indexer to pull CreatureNFT and EggNFT events (mint, feed, starve, breed, lay,
// hatch, discard, and standard ERC-721 Transfer) in one pass.
func (c *Client) FilterLogs(ctx context.Context, addresses []common.Address, fromBlock, toBlock uint64) ([]types.Log, error) {
	query := ethereum.FilterQuery{
		FromBlock: new(big.Int).SetUint64(fromBlock),
		ToBlock:   new(big.Int).SetUint64(toBlock),
		Addresses: addresses,
	}
	return c.eth.FilterLogs(ctx, query)
}

// CallViewFunction performs a raw eth_call to a read function of the shape `fn(address)` --
// selector plus one left-padded address argument -- and returns the raw return bytes for the
// caller to decode. Backs 'view_function' Community Quest checks, where the function itself
// (staked balance, points, tier, "isMember", ...) is creator-specified per task, not something
// we have a fixed ABI for the way TokenBalance has for plain ERC-20 balanceOf.
func (c *Client) CallViewFunction(ctx context.Context, contractAddress string, selector [4]byte, wallet string) ([]byte, error) {
	calldata := append(selector[:], common.LeftPadBytes(common.HexToAddress(wallet).Bytes(), 32)...)
	to := common.HexToAddress(contractAddress)
	return c.eth.CallContract(ctx, ethereum.CallMsg{To: &to, Data: calldata}, nil)
}

// CreatureNFTABI exposes the parsed ABI so the indexer can decode CreatureNFT event logs.
func (c *Client) CreatureNFTABI() abi.ABI {
	a, _ := parseABI(creatureNFTABIJSON)
	return a
}

// EggNFTABI exposes the parsed ABI so the indexer can decode EggNFT event logs.
func (c *Client) EggNFTABI() abi.ABI {
	a, _ := parseABI(eggNFTABIJSON)
	return a
}

// MarketplaceABI exposes the parsed ABI so the indexer can decode event logs.
func (c *Client) MarketplaceABI() abi.ABI {
	a, _ := parseABI(marketplaceABIJSON)
	return a
}

func (c *Client) LatestBlock(ctx context.Context) (uint64, error) {
	return c.eth.BlockNumber(ctx)
}

// BlockTime returns the timestamp of the given block. Used by the game-state indexer to compute
// egg hatch times relative to when a log was actually mined, not when the indexer happened to
// process it (which can lag well behind "now" after downtime or while catching up a backlog).
func (c *Client) BlockTime(ctx context.Context, blockNumber uint64) (time.Time, error) {
	header, err := c.eth.HeaderByNumber(ctx, new(big.Int).SetUint64(blockNumber))
	if err != nil {
		return time.Time{}, fmt.Errorf("fetching header for block %d: %w", blockNumber, err)
	}
	return time.Unix(int64(header.Time), 0).UTC(), nil
}

func (c *Client) txOpts(ctx context.Context) *bind.TransactOpts {
	opts := *c.auth
	opts.Context = ctx
	return &opts
}

// GetEscrow reads a challenge's on-chain wager escrow state directly -- the source of truth for
// whether a challenger/acceptor has actually staked, not something the backend trusts a client's
// self-reported tx hash for. status mirrors BattleEscrow.sol's Status enum: 0 None (never
// wagered/wrong id), 1 Open, 2 Accepted, 3 Resolved, 4 Cancelled. Returns primitives rather than a
// struct so callers can define a narrow local interface around this method without importing
// this package, matching the rest of internal/services' convention.
func (c *Client) GetEscrow(ctx context.Context, challengeID int64) (challenger, acceptor string, wagerWei *big.Int, status uint8, err error) {
	if c.battleEscrow == nil {
		return "", "", nil, 0, fmt.Errorf("BattleEscrow not configured (BATTLE_ESCROW_ADDRESS unset)")
	}
	var out []interface{}
	if err := c.battleEscrow.Call(&bind.CallOpts{Context: ctx}, &out, "escrows", big.NewInt(challengeID)); err != nil {
		return "", "", nil, 0, fmt.Errorf("escrows call: %w", err)
	}
	return out[0].(common.Address).Hex(), out[1].(common.Address).Hex(), out[2].(*big.Int), out[3].(uint8), nil
}

// ResolveEscrow releases a wagered duel's pot (minus the platform rake, paid to the escrow's own
// configured treasury) to the winner -- the one BattleEscrow call only the backend's
// RESOLVER_ROLE signer can make, and only after both sides have actually staked.
func (c *Client) ResolveEscrow(ctx context.Context, challengeID int64, winner string) (string, error) {
	if c.battleEscrow == nil {
		return "", fmt.Errorf("BattleEscrow not configured (BATTLE_ESCROW_ADDRESS unset)")
	}
	if c.auth == nil {
		return "", fmt.Errorf("chain client has no signer configured (BACKEND_SIGNER_PRIVATE_KEY unset)")
	}
	tx, err := c.battleEscrow.Transact(c.txOpts(ctx), "resolve", big.NewInt(challengeID), common.HexToAddress(winner))
	if err != nil {
		return "", fmt.Errorf("resolve tx: %w", err)
	}
	return tx.Hash().Hex(), nil
}

// CancelEscrowOnChain refunds an unaccepted escrow -- called by the backend for a challenge that
// expired (15 minutes, same as an unwagered one) without ever being accepted. A challenger can
// also cancel their own unaccepted escrow directly (see BattleEscrow.sol's cancelEscrow); this is
// only the backend-initiated path.
func (c *Client) CancelEscrowOnChain(ctx context.Context, challengeID int64) (string, error) {
	if c.battleEscrow == nil {
		return "", fmt.Errorf("BattleEscrow not configured (BATTLE_ESCROW_ADDRESS unset)")
	}
	if c.auth == nil {
		return "", fmt.Errorf("chain client has no signer configured (BACKEND_SIGNER_PRIVATE_KEY unset)")
	}
	tx, err := c.battleEscrow.Transact(c.txOpts(ctx), "cancelEscrow", big.NewInt(challengeID))
	if err != nil {
		return "", fmt.Errorf("cancelEscrow tx: %w", err)
	}
	return tx.Hash().Hex(), nil
}

// BattleEscrowABI exposes the parsed ABI for wagmi/web3dart-side ABI parity checks if ever needed
// and for any future event-indexing of BattleEscrow.
func (c *Client) BattleEscrowABI() abi.ABI {
	a, _ := parseABI(battleEscrowABIJSON)
	return a
}
