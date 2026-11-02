import type { ReactNode } from 'react'
import {
  HOLD_RING_CIRCUMFERENCE, HOLD_RING_RADIUS, HOLD_RING_SIZE, HOLD_RING_STROKE, holdRingDashOffset,
} from './holdRing'
import './HoldRing.css'

/** Circular progress for a press-and-hold action; fills clockwise from 12 o'clock. */
export function HoldRing({ progress, label, children }: { progress: number; label: string; children?: ReactNode }) {
  const center = HOLD_RING_SIZE / 2
  return (
    <div
      className="hold-ring"
      role="progressbar"
      aria-label={label}
      aria-valuemin={0}
      aria-valuemax={100}
      aria-valuenow={Math.round(progress)}
    >
      <svg viewBox={`0 0 ${HOLD_RING_SIZE} ${HOLD_RING_SIZE}`} aria-hidden="true">
        <circle className="hold-ring__track" cx={center} cy={center} r={HOLD_RING_RADIUS} strokeWidth={HOLD_RING_STROKE} />
        <circle
          className="hold-ring__fill"
          cx={center}
          cy={center}
          r={HOLD_RING_RADIUS}
          strokeWidth={HOLD_RING_STROKE}
          strokeDasharray={HOLD_RING_CIRCUMFERENCE}
          strokeDashoffset={holdRingDashOffset(progress)}
          transform={`rotate(-90 ${center} ${center})`}
        />
      </svg>
      <div className="hold-ring__content">{children}</div>
    </div>
  )
}
