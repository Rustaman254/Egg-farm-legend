export function PendingBanner({ message }: { message: string }) {
  return (
    <div className="card-pop fixed inset-x-4 bottom-20 z-40 mx-auto flex max-w-sm items-center gap-3 rounded-2xl border-[3px] border-border bg-surface px-4 py-3 md:bottom-6">
      <span className="h-4 w-4 shrink-0 animate-spin rounded-full border-2 border-border" style={{ borderTopColor: 'var(--color-brand-red)' }} />
      <span className="text-sm font-bold text-text">{message}</span>
    </div>
  )
}

export function ErrorBanner({ message }: { message: string }) {
  return (
    <div className="card-pop fixed inset-x-4 bottom-20 z-40 mx-auto max-w-sm rounded-2xl border-[3px] border-down bg-surface px-4 py-3 text-sm font-bold text-down md:bottom-6">
      {message}
    </div>
  )
}
