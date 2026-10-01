import { Wallet } from 'lucide-react'
import type { ReactNode } from 'react'
import { activeChain } from '../config/wagmi'
import { useWallet } from '../hooks/useWallet'

export function ConnectWalletGate({ children }: { children: (wallet: string) => ReactNode }) {
  const wallet = useWallet()

  if (wallet.isConnected && wallet.address) {
    if (wallet.isWrongNetwork) {
      return (
        <div className="flex min-h-svh flex-col items-center justify-center gap-4 bg-bg p-6 text-center text-text">
          <div className="text-5xl">🔀</div>
          <h1 className="font-display text-xl font-extrabold">Wrong network</h1>
          <p className="max-w-sm text-sm text-text-muted">
            EggFarm Legends runs on <strong className="text-text">{activeChain.name}</strong>. Switch your wallet's
            network to continue.
          </p>
          <button
            type="button"
            onClick={wallet.switchToActiveChain}
            disabled={wallet.isSwitching}
            className="rounded-full px-6 py-3 font-bold text-white disabled:opacity-60"
            style={{ background: 'var(--color-brand-red)' }}
          >
            {wallet.isSwitching ? 'Switching...' : `Switch to ${activeChain.name}`}
          </button>
        </div>
      )
    }
    return <>{children(wallet.address)}</>
  }

  return (
    <div className="relative flex min-h-svh items-center justify-center overflow-hidden bg-bg p-6 text-text">
      <div className="arcade-grid pointer-events-none absolute inset-0" />

      <div className="card-pop relative flex w-full max-w-md flex-col items-center gap-5 rounded-3xl border-[3px] border-border bg-surface p-10 text-center">
        <div
          className="glow-pulse flex h-20 w-20 items-center justify-center overflow-hidden rounded-full border-[5px] border-white"
          style={{ background: 'var(--color-brand-red)', boxShadow: '0 0 0 3px var(--color-ink)' }}
        >
          <img src="/logo.png" alt="EggFarm Legend" className="h-full w-full scale-125 object-cover" draggable={false} />
        </div>

        <h1 className="font-display text-3xl font-extrabold tracking-tight">
          Gotta Hatch <span style={{ color: 'var(--color-brand-red)' }}>'Em All</span>
        </h1>
        <p className="max-w-xs text-sm text-text-muted">
          Buy, feed, breed, and trade Animora NFTs on Arbitrum. Connect your wallet to start playing.
        </p>

        {!wallet.hasInjectedWallet ? (
          <div className="mt-2 w-full rounded-2xl border-2 border-border bg-surface-2 p-4 text-sm text-text-muted">
            No wallet extension detected. Install{' '}
            <a
              href="https://metamask.io/download/"
              target="_blank"
              rel="noreferrer"
              className="font-bold underline"
              style={{ color: 'var(--color-brand-blue)' }}
            >
              MetaMask
            </a>{' '}
            or another browser wallet configured for Arbitrum, then reload this page.
          </div>
        ) : (
          <>
            {wallet.connectError && <p className="max-w-sm text-xs text-down">{wallet.connectError.message}</p>}
            <button
              type="button"
              onClick={wallet.connect}
              disabled={wallet.isConnecting}
              className="card-pop-sm mt-2 flex w-full items-center justify-center gap-2 rounded-full px-7 py-3.5 font-display font-bold text-white transition-transform active:scale-[0.98] disabled:opacity-60"
              style={{ background: 'var(--color-brand-red)' }}
            >
              <Wallet size={18} strokeWidth={2.25} />
              {wallet.isConnecting ? 'Connecting...' : 'Connect Wallet'}
            </button>
            <p className="text-[11px] font-bold tracking-wide text-text-faint uppercase">MetaMask &amp; other Arbitrum wallets</p>
          </>
        )}
      </div>
    </div>
  )
}
