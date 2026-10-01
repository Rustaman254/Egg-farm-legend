function colorFor(value: number): string {
  if (value <= 20) return 'var(--color-down)'
  if (value <= 50) return 'var(--color-warn)'
  return 'var(--color-up)'
}

export function StatBar({ label, value }: { label: string; value: number }) {
  const color = colorFor(value)
  return (
    <div className="flex flex-col gap-1">
      <div className="flex justify-between text-[11px] font-bold text-text-muted">
        <span>{label}</span>
        <span className="hud-num" style={{ color }}>
          {value}
        </span>
      </div>
      <div className="h-2.5 w-full overflow-hidden rounded-full border border-border bg-surface-2">
        <div
          className="h-full rounded-full transition-all duration-500 ease-out"
          style={{ width: `${value}%`, background: color }}
        />
      </div>
    </div>
  )
}
