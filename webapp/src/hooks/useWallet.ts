import { useAccount, useConnect, useDisconnect, useSwitchChain, type Connector } from 'wagmi'
import { activeChain } from '../config/wagmi'

// MetaMask first, then the rest alphabetically -- it's the wallet the docs and onboarding assume.
function walletOrder(a: Connector, b: Connector): number {
  const aIsMetaMask = a.id === 'io.metamask'
  const bIsMetaMask = b.id === 'io.metamask'
  if (aIsMetaMask !== bIsMetaMask) return aIsMetaMask ? -1 : 1
  return a.name.localeCompare(b.name)
}

export function useWallet() {
  const { address, isConnected, chainId } = useAccount()
  const { connect, connectors, isPending: isConnecting, error: connectError } = useConnect()
  const { disconnect } = useDisconnect()
  const { switchChain, isPending: isSwitching } = useSwitchChain()

  // wagmi discovers every installed extension wallet via EIP-6963 and gives each its own
  // connector (id = the wallet's rdns, e.g. io.metamask). Offer those by name rather than the
  // generic `injected()` connector, which talks to whichever extension grabbed window.ethereum
  // first -- with several wallets installed that's often not the one the player wants, and a
  // misbehaving one (e.g. Binance Web3 Wallet's "Broadcast channel unavailable") blocks connecting
  // entirely. The generic connector stays as a fallback for wallets that don't announce
  // themselves.
  const discovered = connectors.filter((c) => c.type === 'injected' && c.id !== 'injected').sort(walletOrder)
  const generic = connectors.find((c) => c.id === 'injected')
  const wallets = discovered.length > 0 ? discovered : generic ? [generic] : []
  const hasInjectedWallet = wallets.length > 0 && (discovered.length > 0 || (typeof window !== 'undefined' && !!window.ethereum))

  return {
    address,
    isConnected,
    isWrongNetwork: isConnected && chainId !== activeChain.id,
    isConnecting,
    isSwitching,
    connectError,
    hasInjectedWallet,
    wallets,
    connect: (connector: Connector) => connect({ connector }),
    disconnect,
    switchToActiveChain: () => switchChain({ chainId: activeChain.id }),
  }
}
