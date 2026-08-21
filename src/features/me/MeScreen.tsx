import type { ReactNode } from 'react'
import { PrototypeCard, PrototypeSection } from '@/features/prototype/PrototypeUI'
import './MeScreen.css'

type MeLabelKey =
  | 'account'
  | 'safetyCheckin'
  | 'guardianPermissions'
  | 'emergency'
  | 'preferencesUpdates'

export function MeScreen({
  title,
  subtitle,
  account,
  safetyCheckin,
  guardianPermissions,
  emergency,
  emergencyGps,
  preferencesUpdates,
  labels,
}: {
  title: string
  subtitle: string
  account: ReactNode
  safetyCheckin: ReactNode
  guardianPermissions: ReactNode
  emergency: ReactNode
  emergencyGps: ReactNode
  preferencesUpdates: ReactNode
  labels?: Partial<Record<MeLabelKey, string>>
}) {
  return (
    <div className="me-screen" data-me-sections="account,safety-checkin,guardian-permissions,emergency,preferences-updates">
      <header className="me-screen__heading">
        <h1>{title}</h1>
        <p>{subtitle}</p>
      </header>
      {/* 一个区块 = 一张卡。区块标题已经说明了这一块回答什么问题,内部再分卡
          只会让人以为那是几件要分别处理的事。 */}
      <PrototypeSection title={labels?.account ?? 'Account'}>
        <PrototypeCard>{account}</PrototypeCard>
      </PrototypeSection>
      <PrototypeSection title={labels?.safetyCheckin ?? 'Safety Check-in'}>
        <PrototypeCard>{safetyCheckin}</PrototypeCard>
      </PrototypeSection>
      <PrototypeSection title={labels?.guardianPermissions ?? 'Guardian permissions'}>
        <PrototypeCard>
          {guardianPermissions}
          {emergencyGps}
        </PrototypeCard>
      </PrototypeSection>
      <PrototypeSection title={labels?.emergency ?? 'Emergency information'}>
        <PrototypeCard>{emergency}</PrototypeCard>
      </PrototypeSection>
      {/* 语言、外观这类两三行的开关不需要分隔线。分隔线是给密集或多行内容用的,
          放在几行短开关之间只是把它们挤在一起。 */}
      <PrototypeSection title={labels?.preferencesUpdates ?? 'Preferences & Updates'} className="me-section--preferences">
        <PrototypeCard>{preferencesUpdates}</PrototypeCard>
      </PrototypeSection>
    </div>
  )
}
