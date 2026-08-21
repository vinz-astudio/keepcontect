import './RoutineTimeline.css'

export interface TimelineStep {
  /** 这一步会发生什么,用本人的语言,不用系统的语言。 */
  label: string
  /** 什么时候发生。时刻或时长,不混用。 */
  value: string
  tone: 'quiet' | 'ask' | 'escalate'
}

/**
 * 这个页面真正要回答的问题只有一个:什么情况下,谁会被叫来。
 *
 * 原来的做法是把这句话写成一段散文放在设置下面,179 个词。散文的问题不是长,
 * 是它把顺序藏起来了 —— 读者要自己在脑子里把三个时间点排好。这条时间轴把顺序
 * 画出来,所以它不是装饰,它承载的正是散文里最难读的那部分信息。
 */
export function RoutineTimeline({
  title,
  steps,
  empty,
}: {
  title: string
  steps: TimelineStep[]
  empty?: string
}) {
  return (
    <section className="routine-timeline" aria-label={title}>
      <p className="routine-timeline__title">{title}</p>
      {steps.length === 0 ? (
        <p className="routine-timeline__empty">{empty}</p>
      ) : (
        <ol className="routine-timeline__rail">
          {steps.map((step) => (
            <li key={step.label} className={`routine-timeline__step is-${step.tone}`}>
              <span className="routine-timeline__dot" aria-hidden="true" />
              <span className="routine-timeline__label">{step.label}</span>
              <span className="routine-timeline__value">{step.value}</span>
            </li>
          ))}
        </ol>
      )}
    </section>
  )
}
