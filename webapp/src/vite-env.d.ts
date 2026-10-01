/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_API_BASE_URL: string
  readonly VITE_CHAIN_ID: string
  readonly VITE_ARBITRUM_SEPOLIA_RPC_URL: string
  readonly VITE_ARBITRUM_ONE_RPC_URL: string
  readonly VITE_FEED_TOKEN_ADDRESS: string
  readonly VITE_EGG_NFT_ADDRESS: string
  readonly VITE_CREATURE_NFT_ADDRESS: string
  readonly VITE_MARKETPLACE_ADDRESS: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}

interface Window {
  ethereum?: unknown
}
