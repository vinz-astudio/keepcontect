import { useEffect, useRef, type ReactNode } from 'react'
import './SettingSheet.css'

/**
 * 改一个设置就弹一层,不在列表里就地展开。
 *
 * 就地展开会把清单推开,读者失去「我现在在改哪一项」的位置感,而且一次只能看见
 * 一项的展开态,清单本身反而看不全了。弹层把「看清单」和「改一项」分成两件事。
 */
export function SettingSheet({
  title,
  summary,
  purpose,
  open,
  onClose,
  children,
}: {
  title: string
  /**
   * 这次调整会把什么改成什么。它排在标题之前,因为弹层从底部升上来时,最先进入
   * 视线的就是这一块 —— 而人真正想知道的是后果,不是这个控件叫什么。
   *
   * 警示也放在这里。放在滑条下方的话,弹层贴着屏幕底边,它要么被推出可视区,
   * 要么把滑条顶上去。
   */
  summary?: ReactNode
  /**
   * 这个设置是干什么用的,一句白话。
   *
   * 弹层原来只是把外面那行标题重复一遍,再接一段讲机制的长文 —— 外面一知半解,
   * 点开还是一知半解。真正该补的是「调它会怎样」,而不是「它内部怎么运作」。
   */
  purpose?: string
  open: boolean
  onClose: () => void
  children?: ReactNode
}) {
  const panelRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!open) return
    panelRef.current?.focus()
    const onKey = (event: KeyboardEvent) => { if (event.key === 'Escape') onClose() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, onClose])

  if (!open) return null
  return (
    <div className="setting-sheet" role="presentation" onClick={onClose}>
      <div
        ref={panelRef}
        className="setting-sheet__panel"
        role="dialog"
        aria-modal="true"
        aria-label={title}
        tabIndex={-1}
        onClick={(event) => event.stopPropagation()}
      >
        {summary && <div className="setting-sheet__summary">{summary}</div>}
        <header className="setting-sheet__header">
          <h2>{title}</h2>
          <button type="button" className="setting-sheet__close" onClick={onClose} aria-label="Close">
            ✕
          </button>
        </header>
        <div className="setting-sheet__body">
          {purpose && <p className="setting-sheet__purpose">{purpose}</p>}
          {children}
        </div>
      </div>
    </div>
  )
}
