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

interface SosVisibilityInput {
  isPatternSetup: boolean
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
          { key: 'verify', label: '验证' },
          { key: 'draw', label: '创建' },
          { key: 'confirm', label: '再次确认' },
        ]
      : [
          { key: 'verify', label: 'Verify' },
          { key: 'draw', label: 'Create' },
          { key: 'confirm', label: 'Confirm' },
        ]
  }

  return isZh(lang)
    ? [
        { key: 'draw', label: '创建' },
        { key: 'confirm', label: '再次确认' },
      ]
    : [
        { key: 'draw', label: 'Create' },
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
        ? '画出当前手势以继续。'
        : 'Draw your current pattern to continue.',
      hintKey: 'overlay.hint.verify',
    }
  }

  if (step === 'confirm') {
    return {
      body: isZh(lang)
        ? '再画一次以确认。'
        : 'Draw it again to confirm.',
      hintKey: 'overlay.hint.setup',
    }
  }

  return {
    body: isZh(lang)
      ? '连接至少 4 个点。'
      : 'Connect at least 4 dots.',
    hintKey: 'overlay.hint.setup',
  }
}

export function getPatternSetupIntro(hadOld: boolean, lang: Language): string {
  if (hadOld) {
    return isZh(lang)
      ? '修改用于确认你是否安全的解锁手势。'
      : 'Change the unlock pattern used to confirm you are safe.'
  }

  return isZh(lang)
    ? '创建用于确认你是否安全的解锁手势。'
    : 'Create an unlock pattern used to confirm you are safe.'
}

export function shouldShowSosAction({ isPatternSetup }: SosVisibilityInput): boolean {
  return !isPatternSetup
}

export function getPatternSetupNotice(
  kind: 'verified' | 'captured' | 'mismatch',
  lang: Language,
): string {
  if (kind === 'verified') {
    return isZh(lang)
      ? '验证成功。现在创建新手势。'
      : 'Current pattern verified. Now enter your new pattern.'
  }

  if (kind === 'captured') {
    return isZh(lang)
      ? '已记录。请再画一次确认。'
      : 'New pattern captured. Draw it once more to confirm.'
  }

  return isZh(lang)
    ? '两次不一致。请重新创建手势。'
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
