export type PatternSetupStep = 'verify' | 'draw' | 'confirm'

type Language = 'en' | 'zh' | string

export interface PatternSetupStepLabel {
  key: PatternSetupStep
  label: string
}

export interface PatternSetupText {
  body: string
  hintKey: 'overlay.hint.verify' | 'overlay.hint.setup'
}

function isZh(lang: Language): boolean {
  return lang === 'zh'
}

export function getPatternSetupSteps(
  hadOld: boolean,
  lang: Language,
): PatternSetupStepLabel[] {
  if (hadOld) {
    return isZh(lang)
      ? [
          { key: 'verify', label: '验证当前' },
          { key: 'draw', label: '画新手势' },
          { key: 'confirm', label: '再次确认' },
        ]
      : [
          { key: 'verify', label: 'Verify current' },
          { key: 'draw', label: 'New pattern' },
          { key: 'confirm', label: 'Confirm' },
        ]
  }

  return isZh(lang)
    ? [
        { key: 'draw', label: '画新手势' },
        { key: 'confirm', label: '再次确认' },
      ]
    : [
        { key: 'draw', label: 'New pattern' },
        { key: 'confirm', label: 'Confirm' },
      ]
}

export function getPatternSetupActiveIndex(
  hadOld: boolean,
  step: PatternSetupStep,
): number {
  if (hadOld) {
    return { verify: 0, draw: 1, confirm: 2 }[step]
  }
  return { verify: 0, draw: 0, confirm: 1 }[step]
}

export function getPatternSetupText(
  step: PatternSetupStep,
  lang: Language,
): PatternSetupText {
  if (step === 'verify') {
    return {
      body: isZh(lang)
        ? '先画出当前手势。这一步只验证是你本人，不会修改已保存的手势。'
        : 'First draw your current pattern. This only verifies it is you; it will not change the saved pattern.',
      hintKey: 'overlay.hint.verify',
    }
  }

  if (step === 'confirm') {
    return {
      body: isZh(lang)
        ? '再画一次相同的新手势，匹配后才会保存。'
        : 'Draw the same new pattern once more to save it.',
      hintKey: 'overlay.hint.setup',
    }
  }

  return {
    body: isZh(lang)
      ? '现在画你想使用的新手势。'
      : 'Now draw the new pattern you want to use.',
    hintKey: 'overlay.hint.setup',
  }
}

export function getPatternSetupNotice(
  kind: 'verified' | 'captured' | 'mismatch',
  lang: Language,
): string {
  if (kind === 'verified') {
    return isZh(lang)
      ? '当前手势验证成功。现在请输入新的手势。'
      : 'Current pattern verified. Now enter your new pattern.'
  }

  if (kind === 'captured') {
    return isZh(lang)
      ? '新手势已记录。请再画一次相同手势确认。'
      : 'New pattern captured. Draw it once more to confirm.'
  }

  return isZh(lang)
    ? '两次新手势不一致。请重新输入新手势。'
    : 'The two new patterns did not match. Enter the new pattern again.'
}

export function getPatternSavedMessage(lang: Language): string {
  return isZh(lang) ? '新手势已保存' : 'New pattern saved'
}

export function patternsMatch(
  first: readonly number[] | null,
  second: readonly number[],
): boolean {
  return (
    first != null &&
    first.length === second.length &&
    second.every((value, index) => value === first[index])
  )
}
