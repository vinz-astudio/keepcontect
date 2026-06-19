import { useState } from 'react'
import { useI18n } from '@/lib/i18n'
import './EditableName.css'

interface Props {
  value: string
  canEdit: boolean
  onSave: (next: string) => Promise<void>
  /** 仅作用于非编辑态的显示文本样式 */
  className?: string
}

/** 文本旁带铅笔图标，点击就地编辑（用户名 / Group 名 / Community 名共用） */
export function EditableName({ value, canEdit, onSave, className }: Props) {
  const { t } = useI18n()
  const [editing, setEditing] = useState(false)
  const [draft, setDraft] = useState(value)
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState<string | null>(null)

  async function save() {
    const next = draft.trim()
    if (!next || next === value) {
      setEditing(false)
      return
    }
    setBusy(true)
    setErr(null)
    try {
      await onSave(next)
      setEditing(false)
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'failed')
    } finally {
      setBusy(false)
    }
  }

  if (!editing) {
    return (
      <span className={className}>
        {value}
        {canEdit && (
          <button
            className="editname__icon"
            aria-label={t('edit.aria')}
            title={t('edit.aria')}
            onClick={() => {
              setDraft(value)
              setErr(null)
              setEditing(true)
            }}
          >
            <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
              <rect
                x="2.5"
                y="2.5"
                width="19"
                height="19"
                rx="4"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
              />
              <path
                d="M15 6.2 L17.8 9 L10 16.8 L6.6 17.4 L7.2 14 Z"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinejoin="round"
                strokeLinecap="round"
              />
            </svg>
          </button>
        )}
      </span>
    )
  }

  return (
    <span className="editname">
      <input
        className="editname__input"
        value={draft}
        maxLength={40}
        autoFocus
        disabled={busy}
        onChange={(e) => setDraft(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === 'Enter') void save()
          if (e.key === 'Escape') setEditing(false)
        }}
      />
      <button className="editname__ok" disabled={busy} onClick={() => void save()}>
        ✓
      </button>
      <button
        className="editname__cancel"
        disabled={busy}
        onClick={() => setEditing(false)}
      >
        ✕
      </button>
      {err && <span className="editname__err">{err}</span>}
    </span>
  )
}
