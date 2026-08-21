import { useId, type ReactNode } from 'react'
import './TimeSlider.css'

/**
 * 时长用滑条,不用一排按钮。
 *
 * 上下限本身就是护栏 —— 用户拉不到一个我们知道会误报的值,所以那两个数字必须
 * 看得清,而不是缩在角落里的小字。
 *
 * 拖动过程中只更新本地显示(`onChange`),松手才写(`onCommit`)。否则拖一次
 * 会产生几十次保存,每一次都会在服务端生成一个新的合约版本。
 */
export function TimeSlider({
  label,
  min,
  max,
  step,
  value,
  format,
  disabled,
  onChange,
  onCommit,
  note,
  children,
}: {
  label: string
  min: number
  max: number
  step: number
  value: number
  format: (minutes: number) => string
  disabled?: boolean
  onChange: (minutes: number) => void
  onCommit: (minutes: number) => void
  /** 一句话,放在最后。解释机制内部的说明不属于这里。 */
  note?: string
  children?: ReactNode
}) {
  const id = useId()
  const commit = () => onCommit(value)
  return (
    <div className="time-slider">
      <div className="time-slider__readout">
        <label htmlFor={id} className="time-slider__label">{label}</label>
        <output htmlFor={id} className="time-slider__value">{format(value)}</output>
      </div>
      <input
        id={id}
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        disabled={disabled}
        onChange={(event) => onChange(Number(event.target.value))}
        onPointerUp={commit}
        onKeyUp={commit}
        onBlur={commit}
      />
      <div className="time-slider__ends">
        <span>{format(min)}</span>
        <span>{format(max)}</span>
      </div>
      {children}
      {note && <p className="time-slider__note">{note}</p>}
    </div>
  )
}
