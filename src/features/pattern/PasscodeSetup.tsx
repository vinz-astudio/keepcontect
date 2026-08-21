import { useState } from 'react'
import {
  PASSCODE_MAX_LENGTH,
  PASSCODE_MIN_LENGTH,
  isPasscodeAcceptable,
  setPasscode,
} from './patternStore'
import './PasscodeSetup.css'

/**
 * 数字密码的设置界面。
 *
 * 数字密码和手势是两个独立的凭据,各自都能解锁。界面要把这句话说出来,否则用户
 * 会以为设了这个就把手势换掉了,于是不敢设。
 */
export function PasscodeSetup({
  uid,
  zh,
  onDone,
  onCancel,
}: {
  uid: string
  zh: boolean
  onDone: () => void
  onCancel: () => void
}) {
  const [first, setFirst] = useState('')
  const [second, setSecond] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  const digitsOnly = (value: string) => value.replace(/[^0-9]/g, '').slice(0, PASSCODE_MAX_LENGTH)

  async function save() {
    if (!isPasscodeAcceptable(first)) {
      setError(zh
        ? `请输入 ${PASSCODE_MIN_LENGTH} 到 ${PASSCODE_MAX_LENGTH} 位数字。`
        : `Enter ${PASSCODE_MIN_LENGTH} to ${PASSCODE_MAX_LENGTH} digits.`)
      return
    }
    if (first !== second) {
      setError(zh ? '两次输入不一样。' : 'The two entries do not match.')
      return
    }
    setBusy(true)
    try {
      await setPasscode(uid, first)
      onDone()
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : String(cause))
    }
    setBusy(false)
  }

  return (
    <div className="passcode-setup">
      <p className="passcode-setup__lead">
        {zh
          ? '数字密码和手势各自独立。设了它,手势照样能用 —— 解锁时您挑顺手的那个。'
          : 'The passcode and the pattern are independent. Setting one leaves the other working; at unlock you pick whichever suits.'}
      </p>

      <label className="passcode-setup__field">
        <span>{zh ? '新密码' : 'New passcode'}</span>
        <input
          type="password"
          inputMode="numeric"
          autoComplete="new-password"
          value={first}
          onChange={(e) => { setFirst(digitsOnly(e.target.value)); setError(null) }}
        />
      </label>

      <label className="passcode-setup__field">
        <span>{zh ? '再输入一次' : 'Enter it again'}</span>
        <input
          type="password"
          inputMode="numeric"
          autoComplete="new-password"
          value={second}
          onChange={(e) => { setSecond(digitsOnly(e.target.value)); setError(null) }}
        />
      </label>

      {error && <p className="passcode-setup__error" role="alert">{error}</p>}

      <p className="passcode-setup__note">
        {zh
          ? '这道锁挡的是口袋里的误触,不是别人。它不证明按的人是谁,所以不要用它保管秘密。'
          : 'This lock stops an accidental tap in your pocket. It does not prove who pressed it, so do not treat it as a secret.'}
      </p>

      <div className="passcode-setup__actions">
        <button type="button" className="prototype-button prototype-button--primary" disabled={busy} onClick={() => void save()}>
          {zh ? '保存' : 'Save'}
        </button>
        <button type="button" className="prototype-button prototype-button--ghost" disabled={busy} onClick={onCancel}>
          {zh ? '取消' : 'Cancel'}
        </button>
      </div>
    </div>
  )
}
