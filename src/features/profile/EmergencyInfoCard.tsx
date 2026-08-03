import { useEffect, useState } from 'react'
import {
  getEmergencyInfo,
  saveEmergencyInfo,
  type EmergencyInfoInput,
} from '@/features/profile/emergencyApi'
import { PrototypeCard, PrototypeIcon } from '@/features/prototype/PrototypeUI'
import { useI18n } from '@/lib/i18n'

const EMPTY: EmergencyInfoInput = {
  home_address: '',
  medical_notes: '',
  emergency_contact_name: '',
  emergency_contact_phone: '',
}

type EmergencySection = 'all' | 'contact' | 'address'

function toInput(info: Awaited<ReturnType<typeof getEmergencyInfo>>): EmergencyInfoInput {
  if (!info) return { ...EMPTY }
  return {
    home_address: info.home_address ?? '',
    medical_notes: info.medical_notes ?? '',
    emergency_contact_name: info.emergency_contact_name ?? '',
    emergency_contact_phone: info.emergency_contact_phone ?? '',
  }
}

export function EmergencyInfoCard({ section = 'all' }: { section?: EmergencySection }) {
  const { t, lang } = useI18n()
  const [form, setForm] = useState<EmergencyInfoInput>(EMPTY)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [saved, setSaved] = useState(false)

  useEffect(() => {
    getEmergencyInfo()
      .then((info) => setForm(toInput(info)))
      .catch((caught) => setError(caught instanceof Error ? caught.message : t('err.load')))
      .finally(() => setLoading(false))
  }, [t])

  function field(key: keyof EmergencyInfoInput) {
    return (event: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => {
      setForm((current) => ({ ...current, [key]: event.target.value }))
      setSaved(false)
    }
  }

  async function onSave() {
    setBusy(true)
    setError(null)
    try {
      const latest = toInput(await getEmergencyInfo())
      const merged = section === 'contact'
        ? { ...latest, emergency_contact_name: form.emergency_contact_name, emergency_contact_phone: form.emergency_contact_phone }
        : section === 'address'
          ? { ...latest, home_address: form.home_address, medical_notes: form.medical_notes }
          : form
      await saveEmergencyInfo(merged)
      setForm(merged)
      setSaved(true)
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t('err.op'))
    } finally {
      setBusy(false)
    }
  }

  const showContact = section === 'all' || section === 'contact'
  const showAddress = section === 'all' || section === 'address'

  return (
    <PrototypeCard className="emergency-info-card">
      <div className="emergency-info-card__heading">
        <span><PrototypeIcon name={showContact && !showAddress ? 'contact_phone' : 'home_pin'} /></span>
        <div>
          <strong>{section === 'contact' ? t('ei.contact') : section === 'address' ? t('ei.address') : t('ei.title')}</strong>
          <p>{section === 'contact'
            ? (lang === 'zh' ? '当前版本支持一个紧急联络人；多张联络人卡片仍需后端资料结构支持。' : 'This version supports one emergency contact. Multiple contact cards require the later storage upgrade.')
            : section === 'address'
              ? (lang === 'zh' ? '这是你手写的参考地址，不是设备 GPS 位置。' : 'This is a handwritten reference address, not a device GPS location.')
              : t('ei.desc')}</p>
        </div>
      </div>
      {loading ? <p className="muted">{t('ei.loading')}</p> : (
        <div className="ei emergency-info-card__fields">
          {showContact && (
            <>
              <label className="ei__field"><span>{t('ei.contact')}</span><input value={form.emergency_contact_name} onChange={field('emergency_contact_name')} placeholder={t('ei.contact.ph')} /></label>
              <label className="ei__field"><span>{t('ei.phone')}</span><input type="tel" value={form.emergency_contact_phone} onChange={field('emergency_contact_phone')} placeholder={t('ei.phone.ph')} /></label>
            </>
          )}
          {showAddress && (
            <>
              <label className="ei__field"><span>{t('ei.address')}</span><textarea rows={2} value={form.home_address} onChange={field('home_address')} placeholder={t('ei.address.ph')} /></label>
              <label className="ei__field"><span>{t('ei.medical')}</span><textarea rows={2} value={form.medical_notes} onChange={field('medical_notes')} placeholder={t('ei.medical.ph')} /></label>
            </>
          )}
          {error && <p className="home__error">{error}</p>}
          {saved && <p className="ei__saved">{t('ei.saved')}</p>}
          <button type="button" className="prototype-button prototype-button--primary" disabled={busy} onClick={() => void onSave()}>{busy ? t('ei.saving') : t('ei.save')}</button>
        </div>
      )}
    </PrototypeCard>
  )
}
