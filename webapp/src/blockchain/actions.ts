import { parseEther, type Address } from 'viem'
import { readContract, sendTransaction, waitForTransactionReceipt, watchAsset, writeContract } from 'wagmi/actions'
import { battleEscrowAbi, creatureNftAbi, eggNftAbi, feedTokenAbi, marketplaceAbi } from '../config/abis'
import { CONTRACTS, TREASURY_ADDRESS } from '../config/contracts'
import { BREED_ARB_COST } from '../config/constants'
import { activeChain, wagmiConfig } from '../config/wagmi'

/** Sends a tx via the connected wallet and waits for it to confirm. Every write in this game
 *  goes through the player's own wallet -- the app never holds a private key. */
async function callAndWait(hash: `0x${string}`) {
  await waitForTransactionReceipt(wagmiConfig, { hash, chainId: activeChain.id })
  return hash
}

/** A plain native-currency payment to the platform treasury -- no contract call, just a value
 *  transfer -- used by both the Feed Shop (buying a $FEED package) and partner-quest funding.
 *  The backend verifies the resulting tx hash on-chain before crediting anything (see
 *  internal/chain.Client.VerifyNativePayment), so this function only needs to get the payment
 *  mined and hand back its hash. */
export async function payTreasury(amountWei: bigint) {
  const hash = await sendTransaction(wagmiConfig, {
    to: TREASURY_ADDRESS,
    value: amountWei,
    chainId: activeChain.id,
  })
  return callAndWait(hash)
}

/** Stakes a challenger's wager on BattleEscrow for a challenge id the backend has already
 *  assigned (see battle.Service.CreateChallenge) -- called after the backend confirms the
 *  challenge row exists, before telling the backend the escrow is funded (ConfirmEscrow). */
export async function createBattleEscrow(challengeId: number, wagerWei: bigint) {
  const hash = await writeContract(wagmiConfig, {
    address: CONTRACTS.battleEscrow,
    abi: battleEscrowAbi,
    functionName: 'createEscrow',
    args: [BigInt(challengeId)],
    value: wagerWei,
    chainId: activeChain.id,
  })
  return callAndWait(hash)
}

/** Matches the challenger's stake to accept a wagered challenge -- called before hitting the
 *  backend's accept endpoint, which verifies this landed before resolving the duel. */
export async function acceptBattleEscrow(challengeId: number, wagerWei: bigint) {
  const hash = await writeContract(wagmiConfig, {
    address: CONTRACTS.battleEscrow,
    abi: battleEscrowAbi,
    functionName: 'acceptEscrow',
    args: [BigInt(challengeId)],
    value: wagerWei,
    chainId: activeChain.id,
  })
  return callAndWait(hash)
}

/** Refunds an unaccepted wager -- the challenger backing out of their own posted challenge. */
export async function cancelBattleEscrow(challengeId: number) {
  const hash = await writeContract(wagmiConfig, {
    address: CONTRACTS.battleEscrow,
    abi: battleEscrowAbi,
    functionName: 'cancelEscrow',
    args: [BigInt(challengeId)],
    chainId: activeChain.id,
  })
  return callAndWait(hash)
}

export async function feedCreature(tokenId: number) {
  const hash = await writeContract(wagmiConfig, {
    address: CONTRACTS.creatureNft,
    abi: creatureNftAbi,
    functionName: 'feedCreature',
    args: [BigInt(tokenId)],
    chainId: activeChain.id,
  })
  return callAndWait(hash)
}

export async function layEgg(tokenId: number) {
  const hash = await writeContract(wagmiConfig, {
    address: CONTRACTS.creatureNft,
    abi: creatureNftAbi,
    functionName: 'layEgg',
    args: [BigInt(tokenId)],
    chainId: activeChain.id,
  })
  return callAndWait(hash)
}

export async function breedCreatures(parent1: number, parent2: number) {
  const hash = await writeContract(wagmiConfig, {
    address: CONTRACTS.creatureNft,
    abi: creatureNftAbi,
    functionName: 'breedCreatures',
    args: [BigInt(parent1), BigInt(parent2)],
    value: parseEther(BREED_ARB_COST.toString()),
    chainId: activeChain.id,
    // breedCreatures burns FEED, mints an egg via an external call to EggNFT, and sends ETH to
    // the treasury (plus a possible refund) -- eth_estimateGas underestimates this multi-call
    // path on some RPC backends (reproduced against local Anvil), so pin a generous limit
    // instead of trusting automatic estimation.
    gas: 600_000n,
  })
  return callAndWait(hash)
}

export async function hatchEgg(tokenId: number) {
  const hash = await writeContract(wagmiConfig, {
    address: CONTRACTS.eggNft,
    abi: eggNftAbi,
    functionName: 'hatchEgg',
    args: [BigInt(tokenId)],
    chainId: activeChain.id,
  })
  return callAndWait(hash)
}

export async function discardRottenEgg(tokenId: number) {
  const hash = await writeContract(wagmiConfig, {
    address: CONTRACTS.eggNft,
    abi: eggNftAbi,
    functionName: 'discardRottenEgg',
    args: [BigInt(tokenId)],
    chainId: activeChain.id,
  })
  return callAndWait(hash)
}

export async function tendEgg(tokenId: number) {
  const hash = await writeContract(wagmiConfig, {
    address: CONTRACTS.eggNft,
    abi: eggNftAbi,
    functionName: 'tendEgg',
    args: [BigInt(tokenId)],
    chainId: activeChain.id,
  })
  return callAndWait(hash)
}

/** Pays ETH/ARB to skip some or all of an egg's remaining incubation timer -- see
 *  EggNFT.sol's SPEEDUP_PRICE_PER_HOUR and speedUpHatch(). */
export async function speedUpHatch(tokenId: number, priceWei: bigint) {
  const hash = await writeContract(wagmiConfig, {
    address: CONTRACTS.eggNft,
    abi: eggNftAbi,
    functionName: 'speedUpHatch',
    args: [BigInt(tokenId)],
    value: priceWei,
    chainId: activeChain.id,
  })
  return callAndWait(hash)
}

export async function listOnMarketplace(isEgg: boolean, tokenId: number, priceWei: bigint) {
  const nftAddress = isEgg ? CONTRACTS.eggNft : CONTRACTS.creatureNft
  const abi = isEgg ? eggNftAbi : creatureNftAbi

  // Two signed txs: approve the marketplace to pull the NFT, then list it.
  const approveHash = await writeContract(wagmiConfig, {
    address: nftAddress,
    abi,
    functionName: 'approve',
    args: [CONTRACTS.marketplace, BigInt(tokenId)],
    chainId: activeChain.id,
  })
  await callAndWait(approveHash)

  const listHash = await writeContract(wagmiConfig, {
    address: CONTRACTS.marketplace,
    abi: marketplaceAbi,
    functionName: 'listEgg',
    args: [nftAddress, BigInt(tokenId), priceWei],
    chainId: activeChain.id,
  })
  return callAndWait(listHash)
}

export async function buyListing(listingId: number, priceWei: bigint) {
  const hash = await writeContract(wagmiConfig, {
    address: CONTRACTS.marketplace,
    abi: marketplaceAbi,
    functionName: 'buyEgg',
    args: [BigInt(listingId)],
    value: priceWei,
    chainId: activeChain.id,
    gas: 400_000n, // NFT transfer + seller/fee payouts + possible refund; see breedCreatures
  })
  return callAndWait(hash)
}

export async function cancelListing(listingId: number) {
  const hash = await writeContract(wagmiConfig, {
    address: CONTRACTS.marketplace,
    abi: marketplaceAbi,
    functionName: 'cancelListing',
    args: [BigInt(listingId)],
    chainId: activeChain.id,
  })
  return callAndWait(hash)
}

/** Prompts the wallet to import $FEED as a visible token (EIP-747 `wallet_watchAsset`).
 *  $FEED is minted straight to the player's own address on every task claim, but MetaMask (and
 *  most wallets) never auto-list an arbitrary ERC-20 -- without this the balance is real on-chain
 *  but invisible in the wallet UI until the user manually "imports" the token. */
export async function addFeedTokenToWallet() {
  return watchAsset(wagmiConfig, {
    type: 'ERC20',
    options: {
      address: CONTRACTS.feedToken,
      symbol: 'FEED',
      decimals: 18,
    },
  })
}

/** Live on-chain $FEED balance -- a fallback for when the backend's cached balance is stale. */
export async function getFeedBalance(wallet: Address) {
  return readContract(wagmiConfig, {
    address: CONTRACTS.feedToken,
    abi: feedTokenAbi,
    functionName: 'balanceOf',
    args: [wallet],
    chainId: activeChain.id,
  })
}

/** Converts a human-entered ARB price (e.g. "0.15") to wei without float rounding error. */
export function arbToWei(arbAmount: string): bigint {
  return parseEther(arbAmount || '0')
}
