/** Tiny synthesized chime for the incoming-challenge notification -- no audio asset to ship, just
 *  a couple of Web Audio oscillator blips. Browsers block audio until a user gesture has happened
 *  on the page at least once, so a failure here (no gesture yet, or no AudioContext) is silently
 *  swallowed -- the visual toast is the notification of record, sound is a bonus. */
let sharedContext: AudioContext | null = null

function getContext(): AudioContext | null {
  try {
    if (!sharedContext) {
      const Ctor = window.AudioContext || (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext
      if (!Ctor) return null
      sharedContext = new Ctor()
    }
    return sharedContext
  } catch {
    return null
  }
}

export function playChallengeChime() {
  const ctx = getContext()
  if (!ctx) return
  try {
    if (ctx.state === 'suspended') void ctx.resume()
    const notes = [880, 1175] // A5 -> D6, a quick two-note "ding-dong"
    notes.forEach((freq, i) => {
      const osc = ctx.createOscillator()
      const gain = ctx.createGain()
      osc.type = 'sine'
      osc.frequency.value = freq
      const start = ctx.currentTime + i * 0.14
      gain.gain.setValueAtTime(0, start)
      gain.gain.linearRampToValueAtTime(0.2, start + 0.02)
      gain.gain.exponentialRampToValueAtTime(0.001, start + 0.3)
      osc.connect(gain)
      gain.connect(ctx.destination)
      osc.start(start)
      osc.stop(start + 0.32)
    })
  } catch {
    // audio blocked/unsupported -- the visual toast still shows
  }
}
