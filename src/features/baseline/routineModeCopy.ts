import type { Lang } from '@/lib/i18n'

export type RoutineModeValue =
  | 'regular_9to5'
  | 'semester_break'
  | 'shift_irregular'

export interface RoutineModeOption {
  value: RoutineModeValue
  label: string
  description: string
}

export function getRoutineModeSummary(lang: Lang): string {
  return lang === 'zh'
    ? '用于新用户冷启动的作息模板；记录变多后，App 会按你的真实习惯调整。'
    : 'A starting template for new users; as activity builds up, the app adjusts to your real routine.'
}

export function getRoutineModeOptions(lang: Lang): RoutineModeOption[] {
  if (lang === 'zh') {
    return [
      {
        value: 'regular_9to5',
        label: '常规朝九晚五',
        description: '白天活动较多，夜间较安静。',
      },
      {
        value: 'semester_break',
        label: '学期 / 假期交替',
        description: '上课期和假期节奏不同，先给模型更多弹性。',
      },
      {
        value: 'shift_irregular',
        label: '弹性 / 轮班',
        description: '每天时段不固定，初期提醒会更保守。',
      },
    ]
  }

  return [
    {
      value: 'regular_9to5',
      label: 'Regular 9-to-5',
      description: 'More active by day, quieter at night.',
    },
    {
      value: 'semester_break',
      label: 'Semester & Break',
      description: 'Term and break routines differ, so the model starts flexible.',
    },
    {
      value: 'shift_irregular',
      label: 'Flexible / Shift',
      description: 'Days vary a lot, so early alerts start more cautiously.',
    },
  ]
}
