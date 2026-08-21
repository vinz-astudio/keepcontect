import { useEffect, useState } from 'react'
import {
  getEmergencyInfo,
  saveEmergencyInfo,
  type EmergencyInfoInput,
} from '@/features/profile/emergencyApi'
import { PrototypeBadge, PrototypeRow } from '@/features/prototype/PrototypeUI'
import { useI18n } from '@/lib/i18n'

export interface ContactCardItem {
  id: string
  name: string
  phone: string
  relationship?: string
  isPrimary?: boolean
}

export interface AddressCardItem {
  id: string
  label: string
  address: string
  accessCode?: string
  isPrimary?: boolean
}

type EmergencySection = 'all' | 'contact' | 'address'

function parseContacts(nameStr: string, phoneStr: string): ContactCardItem[] {
  if (!nameStr && !phoneStr) return []
  try {
    if (nameStr.startsWith('[') && nameStr.endsWith(']')) {
      const parsed = JSON.parse(nameStr)
      if (Array.isArray(parsed) && parsed.length > 0) return parsed
    }
  } catch (e) {
    // fallback to single contact
  }
  return [
    {
      id: 'contact-1',
      name: nameStr || 'Emergency Contact',
      phone: phoneStr || '',
      relationship: 'Primary Responder',
      isPrimary: true,
    },
  ]
}

function serializeContacts(contacts: ContactCardItem[]): { name: string; phone: string } {
  if (contacts.length === 0) return { name: '', phone: '' }
  if (contacts.length === 1 && !contacts[0].relationship) {
    return { name: contacts[0].name, phone: contacts[0].phone }
  }
  return {
    name: JSON.stringify(contacts),
    phone: contacts[0]?.phone || '',
  }
}

function parseAddresses(addrStr: string): AddressCardItem[] {
  if (!addrStr) return []
  try {
    if (addrStr.startsWith('[') && addrStr.endsWith(']')) {
      const parsed = JSON.parse(addrStr)
      if (Array.isArray(parsed) && parsed.length > 0) return parsed
    }
  } catch (e) {
    // fallback to single address
  }
  return [
    {
      id: 'addr-1',
      label: 'Home',
      address: addrStr,
      accessCode: '',
      isPrimary: true,
    },
  ]
}

function serializeAddresses(addresses: AddressCardItem[]): string {
  if (addresses.length === 0) return ''
  if (addresses.length === 1 && !addresses[0].accessCode && addresses[0].label === 'Home') {
    return addresses[0].address
  }
  return JSON.stringify(addresses)
}

export function EmergencyInfoCard({ section = 'all' }: { section?: EmergencySection }) {
  const { t, lang } = useI18n()
  const [contacts, setContacts] = useState<ContactCardItem[]>([])
  const [addresses, setAddresses] = useState<AddressCardItem[]>([])
  const [medicalNotes, setMedicalNotes] = useState('')
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [saved, setSaved] = useState(false)

  // Editing state for new/existing items
  const [editingContact, setEditingContact] = useState<ContactCardItem | null>(null)
  const [editingAddress, setEditingAddress] = useState<AddressCardItem | null>(null)

  useEffect(() => {
    getEmergencyInfo()
      .then((info) => {
        if (info) {
          setContacts(parseContacts(info.emergency_contact_name ?? '', info.emergency_contact_phone ?? ''))
          setAddresses(parseAddresses(info.home_address ?? ''))
          setMedicalNotes(info.medical_notes ?? '')
        }
      })
      .catch((caught) => setError(caught instanceof Error ? caught.message : t('err.load')))
      .finally(() => setLoading(false))
  }, [t])

  async function persist(newContacts: ContactCardItem[], newAddresses: AddressCardItem[], newNotes: string) {
    setBusy(true)
    setError(null)
    setSaved(false)
    try {
      const contactSer = serializeContacts(newContacts)
      const addressSer = serializeAddresses(newAddresses)
      const input: EmergencyInfoInput = {
        emergency_contact_name: contactSer.name,
        emergency_contact_phone: contactSer.phone,
        home_address: addressSer,
        medical_notes: newNotes,
      }
      await saveEmergencyInfo(input)
      setContacts(newContacts)
      setAddresses(newAddresses)
      setMedicalNotes(newNotes)
      setSaved(true)
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t('err.op'))
    } finally {
      setBusy(false)
    }
  }

  // Contact Handlers
  function saveContactItem(item: ContactCardItem) {
    let updated: ContactCardItem[]
    if (contacts.some((c) => c.id === item.id)) {
      updated = contacts.map((c) => (c.id === item.id ? item : c))
    } else {
      updated = [...contacts, item]
    }
    if (item.isPrimary) {
      updated = updated.map((c) => ({ ...c, isPrimary: c.id === item.id }))
    }
    setEditingContact(null)
    void persist(updated, addresses, medicalNotes)
  }

  function removeContactItem(id: string) {
    const updated = contacts.filter((c) => c.id !== id)
    if (updated.length > 0 && !updated.some((c) => c.isPrimary)) {
      updated[0].isPrimary = true
    }
    void persist(updated, addresses, medicalNotes)
  }

  function setPrimaryContact(id: string) {
    const updated = contacts.map((c) => ({ ...c, isPrimary: c.id === id }))
    void persist(updated, addresses, medicalNotes)
  }

  // Address Handlers
  function saveAddressItem(item: AddressCardItem) {
    let updated: AddressCardItem[]
    if (addresses.some((a) => a.id === item.id)) {
      updated = addresses.map((a) => (a.id === item.id ? item : a))
    } else {
      updated = [...addresses, item]
    }
    if (item.isPrimary) {
      updated = updated.map((a) => ({ ...a, isPrimary: a.id === item.id }))
    }
    setEditingAddress(null)
    void persist(contacts, updated, medicalNotes)
  }

  function removeAddressItem(id: string) {
    const updated = addresses.filter((a) => a.id !== id)
    if (updated.length > 0 && !updated.some((a) => a.isPrimary)) {
      updated[0].isPrimary = true
    }
    void persist(contacts, updated, medicalNotes)
  }

  function setPrimaryAddress(id: string) {
    const updated = addresses.map((a) => ({ ...a, isPrimary: a.id === id }))
    void persist(contacts, updated, medicalNotes)
  }

  const showContact = section === 'all' || section === 'contact'
  const showAddress = section === 'all' || section === 'address'

  if (loading) {
    return (
      <p className="muted">{t('ei.loading')}</p>
    )
  }

  return (
    <div className="emergency-info-card">
      {/* SECTION: EMERGENCY CONTACTS */}
      {showContact && (
        <div className="emergency-info-card__block">
          <div className="emergency-info-card__header-row">
            <div>
              <strong>{lang === 'zh' ? '紧急联络人' : 'Emergency Contacts'}</strong>
              <p>{lang === 'zh' ? '危机发生时授权接收通知的救援联络人卡片组。' : 'Authorized crisis responders for emergency info.'}</p>
            </div>
            <button
              type="button"
              className="prototype-button prototype-button--ghost"
              onClick={() =>
                setEditingContact({
                  id: `contact-${Date.now()}`,
                  name: '',
                  phone: '',
                  relationship: lang === 'zh' ? '家属 / 亲友' : 'Family / Friend',
                  isPrimary: contacts.length === 0,
                })
              }
            >
              <span>{lang === 'zh' ? '+ 添加' : '+ Add'}</span>
            </button>
          </div>

          {/* Form Modal/Card for Adding/Editing Contact */}
          {editingContact && (
            <div className="emergency-info-card__form-box">
              <label className="ei__field">
                <span>{lang === 'zh' ? '姓名' : 'Name'}</span>
                <input
                  value={editingContact.name}
                  onChange={(e) => setEditingContact({ ...editingContact, name: e.target.value })}
                  placeholder={lang === 'zh' ? '如：Sarah Jenkins' : 'e.g. Sarah Jenkins'}
                />
              </label>
              <label className="ei__field">
                <span>{lang === 'zh' ? '电话号码' : 'Phone'}</span>
                <input
                  type="tel"
                  value={editingContact.phone}
                  onChange={(e) => setEditingContact({ ...editingContact, phone: e.target.value })}
                  placeholder={lang === 'zh' ? '如：+86 13800138000' : 'e.g. +1 (555) 234-5678'}
                />
              </label>
              <label className="ei__field">
                <span>{lang === 'zh' ? '关系 / 角色' : 'Relationship'}</span>
                <input
                  value={editingContact.relationship || ''}
                  onChange={(e) => setEditingContact({ ...editingContact, relationship: e.target.value })}
                  placeholder={lang === 'zh' ? '如：姐妹 / 第一紧急人' : 'e.g. Sister / Primary'}
                />
              </label>
              <label className="home-prototype__toggle-row" style={{ marginTop: 4 }}>
                <input
                  type="checkbox"
                  checked={editingContact.isPrimary}
                  onChange={(e) => setEditingContact({ ...editingContact, isPrimary: e.target.checked })}
                />
                <span>{lang === 'zh' ? '设为主紧急联络人' : 'Set as Primary Contact'}</span>
              </label>
              <div className="home-prototype__button-row" style={{ marginTop: 10 }}>
                <button
                  type="button"
                  className="prototype-button prototype-button--primary"
                  disabled={busy || !editingContact.name.trim() || !editingContact.phone.trim()}
                  onClick={() => saveContactItem(editingContact)}
                >
                  {lang === 'zh' ? '保存联络人' : 'Save Contact'}
                </button>
                <button
                  type="button"
                  className="prototype-button prototype-button--ghost"
                  onClick={() => setEditingContact(null)}
                >
                  {lang === 'zh' ? '取消' : 'Cancel'}
                </button>
              </div>
            </div>
          )}

          {/* Contact Cards Stack */}
          <div className="home-prototype__stack" style={{ gap: 10, marginTop: 12 }}>
            {contacts.length === 0 ? (
              <p className="muted" style={{ fontSize: '0.82rem' }}>
                {lang === 'zh' ? '暂未添加紧急联络人。点击右上角添加。' : 'No emergency contacts added yet.'}
              </p>
            ) : (
              contacts.map((c) => (
                <div key={c.id} className="emergency-info-card__item">
                  <PrototypeRow
                    icon="contact_phone"
                    title={c.name}
                    subtitle={`${c.phone}${c.relationship ? ` · ${c.relationship}` : ''}`}
                    trailing={
                      <PrototypeBadge tone={c.isPrimary ? 'ready' : 'limited'}>
                        {c.isPrimary ? (lang === 'zh' ? '主联络人' : 'Primary') : (lang === 'zh' ? '备用' : 'Secondary')}
                      </PrototypeBadge>
                    }
                  />
                  <div className="home-prototype__button-row" style={{ marginTop: 8 }}>
                    <button
                      type="button"
                      className="prototype-button prototype-button--ghost"
                      onClick={() => setEditingContact(c)}
                    >
                      {lang === 'zh' ? '编辑' : 'Edit'}
                    </button>
                    {!c.isPrimary && (
                      <button
                        type="button"
                        className="prototype-button prototype-button--ghost"
                        onClick={() => setPrimaryContact(c.id)}
                      >
                        {lang === 'zh' ? '设为主联络人' : 'Make Primary'}
                      </button>
                    )}
                    <button
                      type="button"
                      className="prototype-button home-prototype__danger"
                      onClick={() => removeContactItem(c.id)}
                    >
                      {lang === 'zh' ? '删除' : 'Remove'}
                    </button>
                  </div>
                </div>
              ))
            )}
          </div>
        </div>
      )}

      {/* SECTION: EMERGENCY ADDRESSES */}
      {showAddress && (
        <div className="emergency-info-card__block">
          <div className="emergency-info-card__header-row">
            <div>
              <strong>{lang === 'zh' ? '预存物理地址与备注' : 'Emergency Addresses & Notes'}</strong>
              <p>{lang === 'zh' ? '预置常驻物理地址、门禁密码与医疗说明（非实时 GPS）。' : 'Saved static reference locations and medical notes.'}</p>
            </div>
            <button
              type="button"
              className="prototype-button prototype-button--ghost"
              onClick={() =>
                setEditingAddress({
                  id: `addr-${Date.now()}`,
                  label: lang === 'zh' ? '家' : 'Home',
                  address: '',
                  accessCode: '',
                  isPrimary: addresses.length === 0,
                })
              }
            >
              <span>{lang === 'zh' ? '+ 添加' : '+ Add'}</span>
            </button>
          </div>

          {/* Form Modal/Card for Adding/Editing Address */}
          {editingAddress && (
            <div className="emergency-info-card__form-box">
              <label className="ei__field">
                <span>{lang === 'zh' ? '地址标签' : 'Label'}</span>
                <input
                  value={editingAddress.label}
                  onChange={(e) => setEditingAddress({ ...editingAddress, label: e.target.value })}
                  placeholder={lang === 'zh' ? '如：家 / 单位 / 父母家' : 'e.g. Home / Office'}
                />
              </label>
              <label className="ei__field">
                <span>{lang === 'zh' ? '详细物理地址' : 'Address'}</span>
                <textarea
                  rows={2}
                  value={editingAddress.address}
                  onChange={(e) => setEditingAddress({ ...editingAddress, address: e.target.value })}
                  placeholder={lang === 'zh' ? '如：北京市朝阳区某某路 8 号院 3 号楼 502' : 'Full street address'}
                />
              </label>
              <label className="ei__field">
                <span>{lang === 'zh' ? '门禁/钥匙备注' : 'Key & Entry Notes'}</span>
                <input
                  value={editingAddress.accessCode || ''}
                  onChange={(e) => setEditingAddress({ ...editingAddress, accessCode: e.target.value })}
                  placeholder={lang === 'zh' ? '如：门禁密码 #1234，备用钥匙在门口地毯下' : 'e.g. Gate code #1234, key under pot'}
                />
              </label>
              <label className="home-prototype__toggle-row" style={{ marginTop: 4 }}>
                <input
                  type="checkbox"
                  checked={editingAddress.isPrimary}
                  onChange={(e) => setEditingAddress({ ...editingAddress, isPrimary: e.target.checked })}
                />
                <span>{lang === 'zh' ? '设为主预存地址' : 'Set as Primary Address'}</span>
              </label>
              <div className="home-prototype__button-row" style={{ marginTop: 10 }}>
                <button
                  type="button"
                  className="prototype-button prototype-button--primary"
                  disabled={busy || !editingAddress.address.trim()}
                  onClick={() => saveAddressItem(editingAddress)}
                >
                  {lang === 'zh' ? '保存地址' : 'Save Address'}
                </button>
                <button
                  type="button"
                  className="prototype-button prototype-button--ghost"
                  onClick={() => setEditingAddress(null)}
                >
                  {lang === 'zh' ? '取消' : 'Cancel'}
                </button>
              </div>
            </div>
          )}

          {/* Address Cards Stack */}
          <div className="home-prototype__stack" style={{ gap: 10, marginTop: 12 }}>
            {addresses.length === 0 ? (
              <p className="muted" style={{ fontSize: '0.82rem' }}>
                {lang === 'zh' ? '暂未预存物理地址。点击右上角添加。' : 'No emergency addresses added yet.'}
              </p>
            ) : (
              addresses.map((a) => (
                <div key={a.id} className="emergency-info-card__item">
                  <PrototypeRow
                    icon="home_pin"
                    title={a.label || 'Home'}
                    subtitle={`${a.address}${a.accessCode ? ` · 备注: ${a.accessCode}` : ''}`}
                    trailing={
                      <PrototypeBadge tone={a.isPrimary ? 'ready' : 'limited'}>
                        {a.isPrimary ? (lang === 'zh' ? '主地址' : 'Primary') : (lang === 'zh' ? '备用地址' : 'Secondary')}
                      </PrototypeBadge>
                    }
                  />
                  <div className="home-prototype__button-row" style={{ marginTop: 8 }}>
                    <button
                      type="button"
                      className="prototype-button prototype-button--ghost"
                      onClick={() => setEditingAddress(a)}
                    >
                      {lang === 'zh' ? '编辑' : 'Edit'}
                    </button>
                    {!a.isPrimary && (
                      <button
                        type="button"
                        className="prototype-button prototype-button--ghost"
                        onClick={() => setPrimaryAddress(a.id)}
                      >
                        {lang === 'zh' ? '设为主地址' : 'Make Primary'}
                      </button>
                    )}
                    <button
                      type="button"
                      className="prototype-button home-prototype__danger"
                      onClick={() => removeAddressItem(a.id)}
                    >
                      {lang === 'zh' ? '删除' : 'Remove'}
                    </button>
                  </div>
                </div>
              ))
            )}
          </div>

          {/* Medical Notes Text Area */}
          <div className="ei__field" style={{ marginTop: 14, paddingTop: 12, borderTop: '1px solid var(--line)' }}>
            <span style={{ fontSize: '0.82rem', fontWeight: 500 }}>{lang === 'zh' ? '医疗与过敏特殊说明' : 'Medical & Allergy Notes'}</span>
            <textarea
              rows={2}
              value={medicalNotes}
              onChange={(e) => setMedicalNotes(e.target.value)}
              placeholder={lang === 'zh' ? '如：对青霉素过敏，有哮喘病史，常用药放在客厅抽屉' : 'e.g. Allergic to Penicillin, asthma history'}
            />
            <button
              type="button"
              className="prototype-button prototype-button--ghost"
              style={{ marginTop: 8, alignSelf: 'flex-start' }}
              disabled={busy}
              onClick={() => void persist(contacts, addresses, medicalNotes)}
            >
              {lang === 'zh' ? '更新医疗说明' : 'Save Medical Notes'}
            </button>
          </div>
        </div>
      )}

      {error && <p className="home__error">{error}</p>}
      {saved && <p className="ei__saved">{t('ei.saved')}</p>}
    </div>
  )
}
