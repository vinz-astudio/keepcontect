import { useEffect, useState } from 'react'
import {
  getEmergencyInfo,
  saveEmergencyInfo,
  type EmergencyInfoInput,
} from '@/features/profile/emergencyApi'
import { useI18n } from '@/lib/i18n'
import { Icon } from '@/features/common/Icon'

const EMPTY: EmergencyInfoInput = {
  home_address: '',
  medical_notes: '',
  emergency_contact_name: '',
  emergency_contact_phone: '',
}

export function EmergencyInfoCard() {
  const { t } = useI18n()
  const [form, setForm] = useState<EmergencyInfoInput>(EMPTY)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [saved, setSaved] = useState(false)

  useEffect(() => {
    getEmergencyInfo()
      .then((info) => {
        if (info) {
          setForm({
            home_address: info.home_address ?? '',
            medical_notes: info.medical_notes ?? '',
            emergency_contact_name: info.emergency_contact_name ?? '',
            emergency_contact_phone: info.emergency_contact_phone ?? '',
          })
        }
      })
      .catch((e) => setError(e instanceof Error ? e.message : '加载失败'))
      .finally(() => setLoading(false))
  }, [])

  function field(key: keyof EmergencyInfoInput) {
    return (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => {
      setForm((f) => ({ ...f, [key]: e.target.value }))
      setSaved(false)
    }
  }

  async function onSave() {
    setBusy(true)
    setError(null)
    try {
      await saveEmergencyInfo(form)
      setSaved(true)
    } catch (e) {
      setError(e instanceof Error ? e.message : '保存失败')
    } finally {
      setBusy(false)
    }
  }

  return (
    <section className="card">
      <h2 className="card__title">
        <Icon name="heart" />
        {t('ei.title')}
      </h2>
      <p className="muted">{t('ei.desc')}</p>
      {loading ? (
        <p className="muted">{t('ei.loading')}</p>
      ) : (
        <div className="ei">
          <label className="ei__field">
            <span>{t('ei.address')}</span>
            <textarea
              rows={2}
              value={form.home_address}
              onChange={field('home_address')}
              placeholder={t('ei.address.ph')}
            />
          </label>
          <label className="ei__field">
            <span>{t('ei.medical')}</span>
            <textarea
              rows={2}
              value={form.medical_notes}
              onChange={field('medical_notes')}
              placeholder={t('ei.medical.ph')}
            />
          </label>
          <label className="ei__field">
            <span>{t('ei.contact')}</span>
            <input
              value={form.emergency_contact_name}
              onChange={field('emergency_contact_name')}
              placeholder={t('ei.contact.ph')}
            />
          </label>
          <label className="ei__field">
            <span>{t('ei.phone')}</span>
            <input
              type="tel"
              value={form.emergency_contact_phone}
              onChange={field('emergency_contact_phone')}
              placeholder={t('ei.phone.ph')}
            />
          </label>

          {error && <p className="home__error">{error}</p>}
          {saved && <p className="ei__saved">{t('ei.saved')}</p>}

          <button className="ei__save" disabled={busy} onClick={onSave}>
            {busy ? t('ei.saving') : t('ei.save')}
          </button>
        </div>
      )}
    </section>
  )
}
