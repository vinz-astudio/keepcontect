import { PrototypeIcon } from '@/features/prototype/PrototypeUI'
import './SettingRow.css'

/**
 * 清单行只做一件事:说出这一项现在是什么值,并且可以点开去改。
 *
 * 它不再就地展开 —— 展开会把下面的行推走,改一项的时候反而看不见清单了。
 */
export function SettingRow({
  label,
  value,
  note,
  marker = false,
  onOpen,
}: {
  label: string
  value: string
  /** 括号里的换算,比如「2 次」后面的「4 小时」。 */
  note?: string
  /** 属于告警链条的那几项带一个点,和睡眠、时区这类环境设置区分开。 */
  marker?: boolean
  onOpen: () => void
}) {
  return (
    <button type="button" className="setting-row" onClick={onOpen}>
      <span className="setting-row__label">
        {marker && <span className="setting-row__marker" aria-hidden="true" />}
        {label}
      </span>
      <span className="setting-row__value">
        {value}
        {note && <small>{note}</small>}
      </span>
      <PrototypeIcon name="chevron_right" className="setting-row__chevron" />
    </button>
  )
}
