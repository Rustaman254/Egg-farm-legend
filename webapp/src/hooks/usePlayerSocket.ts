import { useEffect, useRef } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { API_BASE_URL } from '../config/contracts'
import type { BattleResult, ChallengeSummary, MarketplaceChangedPayload, PlayerSocketEvent, WalletEventPayload } from '../api/types'

/** Live push channel for the whole app -- arena challenges, wallet-balance/trade notifications,
 *  and marketplace changes all ride the same per-wallet socket. Reconnects with backoff, and on
 *  top of firing the given callbacks, invalidates the same queries the existing short-interval
 *  polls already refresh -- so a push just makes those polls land instantly instead of replacing
 *  them (a dropped/blocked socket, e.g. the browser's Local Network Access gate on a
 *  tunnel-hosted page, degrades gracefully to plain polling rather than losing events outright). */
export function usePlayerSocket(
  wallet: string | undefined,
  handlers: {
    onChallengeReceived?: (challenge: ChallengeSummary) => void
    onChallengeResolved?: (challengeId: number, result: BattleResult) => void
    onWalletEvent?: (event: WalletEventPayload) => void
    onMarketplaceChanged?: (event: MarketplaceChangedPayload) => void
  },
) {
  const queryClient = useQueryClient()
  const handlersRef = useRef(handlers)
  useEffect(() => {
    handlersRef.current = handlers
  }, [handlers])

  useEffect(() => {
    if (!wallet) return
    let socket: WebSocket | null = null
    let reconnectTimer: ReturnType<typeof setTimeout> | null = null
    let closedByEffect = false

    // Resolve against the page origin so a same-origin (empty) API_BASE_URL still yields an
    // absolute ws:// / wss:// URL.
    const wsUrl = new URL(`${API_BASE_URL}/api/players/${wallet}/ws`, window.location.href)
    wsUrl.protocol = wsUrl.protocol === 'https:' ? 'wss:' : 'ws:'

    function connect() {
      socket = new WebSocket(wsUrl)
      socket.onmessage = (event) => {
        let parsed: PlayerSocketEvent
        try {
          parsed = JSON.parse(event.data)
        } catch {
          return
        }
        switch (parsed.type) {
          case 'challenge_received':
            handlersRef.current.onChallengeReceived?.(parsed.payload as ChallengeSummary)
            queryClient.invalidateQueries({ queryKey: ['challenges', 'incoming', wallet] })
            break
          case 'challenge_resolved': {
            const { challengeId, result } = parsed.payload as { challengeId: number; result: BattleResult }
            handlersRef.current.onChallengeResolved?.(challengeId, result)
            queryClient.invalidateQueries({ queryKey: ['challenges', 'mine', wallet] })
            queryClient.invalidateQueries({ queryKey: ['farm', wallet] })
            queryClient.invalidateQueries({ queryKey: ['leaderboard', 'battlers'] })
            break
          }
          case 'wallet_event':
            handlersRef.current.onWalletEvent?.(parsed.payload as WalletEventPayload)
            queryClient.invalidateQueries({ queryKey: ['activity', wallet] })
            queryClient.invalidateQueries({ queryKey: ['farm', wallet] })
            break
          case 'marketplace_changed':
            handlersRef.current.onMarketplaceChanged?.(parsed.payload as MarketplaceChangedPayload)
            queryClient.invalidateQueries({ queryKey: ['listings'] })
            break
        }
      }
      socket.onclose = () => {
        if (closedByEffect) return
        reconnectTimer = setTimeout(connect, 3_000)
      }
      socket.onerror = () => socket?.close()
    }
    connect()

    return () => {
      closedByEffect = true
      if (reconnectTimer) clearTimeout(reconnectTimer)
      socket?.close()
    }
  }, [wallet, queryClient])
}
