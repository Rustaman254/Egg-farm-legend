import { useAccount, useConnect, useDisconnect, useSwitchChain } from 'wagmi'
import { activeChain } from '../config/wagmi'

export function useWallet() {
  const { address, isConnected, chainId } = useAccount()
  const { connect, connectors, isPending: isConnecting, error: connectError } = useConnect()
  const { disconnect } = useDisconnect()
  const { switchChain, isPending: isSwitching } = useSwitchChain()

  // `injected()` matches MetaMask and any other EIP-1193 browser extension wallet.
  const injectedConnector = connectors.find((c) => c.id === 'injected') ?? connectors[0]
  const hasInjectedWallet = typeof window !== 'undefined' && !!window.ethereum

  return {
    address,
    isConnected,
    isWrongNetwork: isConnected && chainId !== activeChain.id,
    isConnecting,
    isSwitching,
    connectError,
    hasInjectedWallet,
    connect: () => injectedConnector && connect({ connector: injectedConnector }),
    disconnect,
    switchToActiveChain: () => switchChain({ chainId: activeChain.id }),
  }
}
