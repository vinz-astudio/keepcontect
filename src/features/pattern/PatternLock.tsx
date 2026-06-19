import { useRef, useState, type PointerEvent as ReactPointerEvent } from 'react'
import { useI18n } from '@/lib/i18n'
import './PatternLock.css'

interface Props {
  minLength?: number
  onComplete: (seq: number[]) => void
  hint?: string
}

// 两点之间被"跨过"的中间点（与传统手势一致：直线经过的点会自动连上）
const MID: Record<string, number> = {
  '0-2': 1, '2-0': 1, '3-5': 4, '5-3': 4, '6-8': 7, '8-6': 7,
  '0-6': 3, '6-0': 3, '1-7': 4, '7-1': 4, '2-8': 5, '8-2': 5,
  '0-8': 4, '8-0': 4, '2-6': 4, '6-2': 4,
}

interface Center {
  x: number
  y: number
  r: number
}

/**
 * 九宫格连线手势：按住一个点，连续拖动经过其他点连成一笔，松手即提交。
 * 与手机传统解锁屏幕逻辑一致。序列为经过的点索引（0–8），存哈希、不存明文。
 */
export function PatternLock({ minLength = 4, onComplete, hint }: Props) {
  const { t } = useI18n()
  const gridRef = useRef<HTMLDivElement>(null)
  const dotRefs = useRef<Array<HTMLDivElement | null>>([])
  const drawing = useRef(false)
  const seqRef = useRef<number[]>([]) // 事件处理里读最新序列，避免在 setState 更新器里做副作用
  const [seq, setSeq] = useState<number[]>([])
  const [cursor, setCursor] = useState<{ x: number; y: number } | null>(null)
  const [tooShort, setTooShort] = useState(false)

  function centers(): Center[] {
    const g = gridRef.current?.getBoundingClientRect()
    if (!g) return []
    return dotRefs.current.map((el) => {
      const r = el!.getBoundingClientRect()
      return {
        x: r.left + r.width / 2 - g.left,
        y: r.top + r.height / 2 - g.top,
        r: r.width / 2,
      }
    })
  }

  function addDot(i: number) {
    const prev = seqRef.current
    if (prev.includes(i)) return
    let next = prev
    if (prev.length) {
      const mid = MID[`${prev[prev.length - 1]}-${i}`]
      if (mid !== undefined && !prev.includes(mid)) next = [...next, mid]
    }
    next = [...next, i]
    seqRef.current = next
    setSeq(next)
  }

  function locate(e: ReactPointerEvent) {
    const g = gridRef.current?.getBoundingClientRect()
    if (!g) return
    const x = e.clientX - g.left
    const y = e.clientY - g.top
    setCursor({ x, y })
    const cs = centers()
    for (let i = 0; i < 9; i++) {
      // 命中半径略大于圆点，方便连线（但不至于误触相邻点）
      if (Math.hypot(x - cs[i].x, y - cs[i].y) <= cs[i].r * 1.25) {
        addDot(i)
        break
      }
    }
  }

  function down(e: ReactPointerEvent) {
    drawing.current = true
    setTooShort(false)
    seqRef.current = []
    setSeq([])
    gridRef.current?.setPointerCapture(e.pointerId)
    locate(e)
  }

  function move(e: ReactPointerEvent) {
    if (drawing.current) locate(e)
  }

  function up() {
    if (!drawing.current) return
    drawing.current = false
    setCursor(null)
    const final = seqRef.current
    if (final.length >= minLength) {
      onComplete(final) // 事件处理内调用，不在渲染期
    } else {
      if (final.length > 0) setTooShort(true)
      seqRef.current = []
      setSeq([])
    }
  }

  const cs = centers()
  const linePts = seq.map((i) => cs[i]).filter(Boolean)
  const last = linePts[linePts.length - 1]

  return (
    <div className="pattern">
      {hint && <p className="pattern__hint">{hint}</p>}
      <div
        className="pattern__grid"
        ref={gridRef}
        role="application"
        aria-label={hint}
        onPointerDown={down}
        onPointerMove={move}
        onPointerUp={up}
        onPointerCancel={up}
      >
        <svg className="pattern__lines" aria-hidden="true">
          {linePts.length > 1 && (
            <polyline points={linePts.map((p) => `${p.x},${p.y}`).join(' ')} />
          )}
          {drawing.current && last && cursor && (
            <line x1={last.x} y1={last.y} x2={cursor.x} y2={cursor.y} />
          )}
        </svg>
        {Array.from({ length: 9 }, (_, i) => (
          <div
            key={i}
            ref={(el) => {
              dotRefs.current[i] = el
            }}
            className={`pattern__dot${seq.includes(i) ? ' is-on' : ''}`}
          >
            <span className="pattern__core" />
          </div>
        ))}
      </div>
      {tooShort && (
        <p className="pattern__warn">{t('pattern.tooShort', { min: minLength })}</p>
      )}
    </div>
  )
}
