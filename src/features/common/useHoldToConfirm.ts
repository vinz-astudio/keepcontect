import { useEffect, useRef, useState, type KeyboardEvent, type PointerEvent } from 'react'
import { holdProgress } from './holdProgress'

/**
 * Press-and-hold for pointer and keyboard (Space/Enter). onComplete fires once
 * when the hold reaches 100%; releasing earlier cancels and calls onEarlyRelease.
 */
export function useHoldToConfirm(options: {
  durationMs: number
  disabled?: boolean
  onComplete: () => void
  onEarlyRelease?: () => void
}) {
  const { durationMs, disabled } = options
  const [progress, setProgress] = useState(0)
  const [holding, setHolding] = useState(false)
  const startedAt = useRef<number | null>(null)
  const frame = useRef<number | null>(null)
  const latest = useRef(options)
  latest.current = options

  const stop = () => {
    if (frame.current !== null) cancelAnimationFrame(frame.current)
    frame.current = null
    startedAt.current = null
    setHolding(false)
    setProgress(0)
  }

  useEffect(() => () => {
    if (frame.current !== null) cancelAnimationFrame(frame.current)
  }, [])

  const tick = (now: number) => {
    const p = holdProgress(startedAt.current, now, durationMs)
    setProgress(p)
    if (p >= 100) {
      stop()
      latest.current.onComplete()
      return
    }
    frame.current = requestAnimationFrame(tick)
  }

  const start = () => {
    if (disabled || startedAt.current !== null) return
    startedAt.current = performance.now()
    setHolding(true)
    frame.current = requestAnimationFrame(tick)
  }

  const release = (early: boolean) => {
    if (startedAt.current === null) return
    stop()
    if (early) latest.current.onEarlyRelease?.()
  }

  const isHoldKey = (key: string) => key === ' ' || key === 'Enter'

  return {
    progress,
    holding,
    handlers: {
      onPointerDown: (event: PointerEvent<HTMLElement>) => {
        event.preventDefault()
        event.currentTarget.setPointerCapture?.(event.pointerId)
        start()
      },
      onPointerUp: () => release(true),
      onPointerCancel: () => release(false),
      onLostPointerCapture: () => release(false),
      onKeyDown: (event: KeyboardEvent<HTMLElement>) => {
        if (!isHoldKey(event.key)) return
        event.preventDefault()
        if (!event.repeat) start()
      },
      onKeyUp: (event: KeyboardEvent<HTMLElement>) => {
        if (!isHoldKey(event.key)) return
        event.preventDefault()
        release(true)
      },
      // A long press on a phone would otherwise open the text/context menu.
      onContextMenu: (event: { preventDefault: () => void }) => event.preventDefault(),
    },
  }
}
