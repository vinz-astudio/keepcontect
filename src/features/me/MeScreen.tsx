import type { ReactNode } from 'react'
import { PrototypeSection } from '@/features/prototype/PrototypeUI'
import './MeScreen.css'

type MeLabelKey =
  | 'account'
  | 'safetyCheckin'
  | 'thisDevice'
  | 'linkedDevices'
  | 'emergencyContacts'
  | 'emergencyAddresses'
  | 'emergencyGps'
  | 'preferencesUpdates'

export function MeScreen({
  title,
  subtitle,
  account,
  safetyCheckin,
  thisDevice,
  linkedDevices,
  emergencyContacts,
  emergencyAddresses,
  emergencyGps,
  preferencesUpdates,
  labels,
}: {
  title: string
  subtitle: string
  account: ReactNode
  safetyCheckin: ReactNode
  thisDevice: ReactNode
  linkedDevices: ReactNode
  emergencyContacts: ReactNode
  emergencyAddresses: ReactNode
  emergencyGps: ReactNode
  preferencesUpdates: ReactNode
  labels?: Partial<Record<MeLabelKey, string>>
}) {
  return (
    <div className="me-screen" data-me-sections="account,safety-checkin,this-device,linked-devices,emergency-contacts,emergency-addresses,emergency-gps,preferences-updates">
      <header className="me-screen__heading">
        <h1>{title}</h1>
        <p>{subtitle}</p>
      </header>
      <PrototypeSection title={labels?.account ?? 'Account'}>{account}</PrototypeSection>
      <PrototypeSection title={labels?.safetyCheckin ?? 'Safety Check-in'}>{safetyCheckin}</PrototypeSection>
      <PrototypeSection title={labels?.thisDevice ?? 'This Device'}>{thisDevice}</PrototypeSection>
      <PrototypeSection title={labels?.linkedDevices ?? 'Linked Devices'}>{linkedDevices}</PrototypeSection>
      <PrototypeSection title={labels?.emergencyContacts ?? 'Emergency Contacts'}>{emergencyContacts}</PrototypeSection>
      <PrototypeSection title={labels?.emergencyAddresses ?? 'Emergency Addresses'}>{emergencyAddresses}</PrototypeSection>
      <PrototypeSection title={labels?.emergencyGps ?? 'Emergency GPS'}>{emergencyGps}</PrototypeSection>
      <PrototypeSection title={labels?.preferencesUpdates ?? 'Preferences & Updates'}>{preferencesUpdates}</PrototypeSection>
    </div>
  )
}
