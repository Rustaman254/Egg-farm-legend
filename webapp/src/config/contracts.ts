import type { Address } from 'viem'

function requireAddress(envValue: string | undefined, name: string): Address {
  if (!envValue) {
    console.warn(`${name} is not set (see .env.example) -- contract calls will fail until it is`)
    return '0x0000000000000000000000000000000000000000'
  }
  return envValue as Address
}

export const CONTRACTS = {
  feedToken: requireAddress(import.meta.env.VITE_FEED_TOKEN_ADDRESS, 'VITE_FEED_TOKEN_ADDRESS'),
  eggNft: requireAddress(import.meta.env.VITE_EGG_NFT_ADDRESS, 'VITE_EGG_NFT_ADDRESS'),
  creatureNft: requireAddress(import.meta.env.VITE_CREATURE_NFT_ADDRESS, 'VITE_CREATURE_NFT_ADDRESS'),
  marketplace: requireAddress(import.meta.env.VITE_MARKETPLACE_ADDRESS, 'VITE_MARKETPLACE_ADDRESS'),
  battleEscrow: requireAddress(import.meta.env.VITE_BATTLE_ESCROW_ADDRESS, 'VITE_BATTLE_ESCROW_ADDRESS'),
} as const

export const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || 'http://localhost:8080'

// Where Feed Shop purchases and partner-quest funding payments go (see backend's
// TREASURY_ADDRESS) -- not a game contract, just an EOA, so it's not part of CONTRACTS above.
export const TREASURY_ADDRESS = requireAddress(import.meta.env.VITE_TREASURY_ADDRESS, 'VITE_TREASURY_ADDRESS')
