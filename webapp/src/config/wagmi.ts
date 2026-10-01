import { createConfig, http, injected } from 'wagmi'
import { arbitrum, arbitrumSepolia } from 'wagmi/chains'
import { defineChain } from 'viem'

// A local Foundry/Anvil node (`anvil`), for testing the full stack (wallet + backend +
// contracts) without spending real testnet ETH. Add it to MetaMask as a custom network:
// RPC http://127.0.0.1:8545, Chain ID 31337, currency ETH.
export const anvilLocal = defineChain({
  id: 31337,
  name: 'EggFarm Local (Anvil)',
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: { default: { http: ['http://127.0.0.1:8545'] } },
})

// Injected covers MetaMask and any other EIP-1193 browser wallet extension (Rabby, Coinbase
// Wallet extension, Arbitrum-compatible hardware-wallet bridges, etc.) -- there's no separate
// "Arbitrum wallet" SDK; any wallet configured for Arbitrum One/Sepolia (or the local Anvil
// chain above) works the same way.
export const wagmiConfig = createConfig({
  chains: [arbitrumSepolia, arbitrum, anvilLocal],
  connectors: [injected()],
  transports: {
    [arbitrumSepolia.id]: http(import.meta.env.VITE_ARBITRUM_SEPOLIA_RPC_URL || undefined),
    [arbitrum.id]: http(import.meta.env.VITE_ARBITRUM_ONE_RPC_URL || undefined),
    [anvilLocal.id]: http('http://127.0.0.1:8545'),
  },
})

const CHAINS_BY_ID = {
  [arbitrumSepolia.id]: arbitrumSepolia,
  [arbitrum.id]: arbitrum,
  [anvilLocal.id]: anvilLocal,
} as const

// The chain this build targets end-to-end (contracts + backend are deployed to one network at a
// time). Defaults to Arbitrum Sepolia; set VITE_CHAIN_ID=31337 to point the app at a local Anvil
// node during development.
const configuredChainId = Number(import.meta.env.VITE_CHAIN_ID || arbitrumSepolia.id)
export const activeChain = CHAINS_BY_ID[configuredChainId as keyof typeof CHAINS_BY_ID] ?? arbitrumSepolia

declare module 'wagmi' {
  interface Register {
    config: typeof wagmiConfig
  }
}
