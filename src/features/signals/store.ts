// 本地行为时序存储（IndexedDB），且当用户登录时支持与 Supabase 双向同步。

import type { SignalEvent, SignalKind } from '@/features/baseline/types'
import { supabase } from '@/lib/supabase'
import { getAutomaticPingSource, PING_SOURCES } from '@/features/passive/api'

const DB_NAME = 'keepcontact'
const STORE = 'signals'
const VERSION = 2

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, VERSION)
    req.onupgradeneeded = () => {
      const db = req.result
      if (!db.objectStoreNames.contains(STORE)) {
        const os = db.createObjectStore(STORE, {
          keyPath: 'id',
          autoIncrement: true,
        })
        os.createIndex('t', 't')
      }
    }
    req.onsuccess = () => resolve(req.result)
    req.onerror = () => reject(req.error)
  })
}

function generateUUID(): string {
  const cryptoObj = typeof window !== 'undefined' ? window.crypto : (globalThis as any).crypto
  if (cryptoObj && typeof cryptoObj.randomUUID === 'function') {
    return cryptoObj.randomUUID()
  }
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = Math.random() * 16 | 0
    const v = c === 'x' ? r : (r & 0x3 | 0x8)
    return v.toString(16)
  })
}

export async function recordSignal(
  kind: SignalKind,
  t: number = Date.now(),
): Promise<void> {
  // Determine source at record time
  let recordSource: string | null = null
  if (kind === 'manual_checkin') {
    recordSource = PING_SOURCES.MANUAL
  } else {
    recordSource = getAutomaticPingSource()
  }

  // Get session user_id or null before storage safely
  let verifiedUserId: string | null = null
  try {
    const { data } = await supabase.auth.getSession()
    verifiedUserId = data?.session?.user?.id ?? null
  } catch {
    verifiedUserId = null
  }
  const event_id = generateUUID()
  const at = new Date(t).toISOString()

  const db = await openDb()
  let addedId: number | undefined
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(STORE, 'readwrite')
    const req = tx.objectStore(STORE).add({
      t,
      at,
      kind,
      uploaded: false,
      quarantined: false,
      quarantine: false,
      source: recordSource,
      event_id,
      user_id: verifiedUserId
    })
    req.onsuccess = () => {
      addedId = req.result as number
      resolve()
    }
    tx.onerror = () => reject(tx.error)
  })
  db.close()

  // Upload debounce: only upload to Supabase if at least 10 minutes have passed since last upload,
  // except for manual checkins (which must be uploaded immediately).
  try {
    const lastUploadStr = localStorage.getItem('kc.lastUploadT')
    const lastUpload = lastUploadStr ? parseInt(lastUploadStr, 10) : 0
    const DEBOUNCE_MS = 10 * 60 * 1000 // 10 minutes

    if (kind === 'manual_checkin' || t - lastUpload >= DEBOUNCE_MS) {
      // If ownerless (quarantined) or plain browser, do not upload
      if (verifiedUserId && recordSource) {
        const { data: status, error } = await supabase.rpc('record_behavior_ping', {
          event_id,
          observed_at: at,
          source: recordSource,
          kind
        })

        if (!error) {
          const isSuccess = status === 'inserted' || status === 'duplicate' || status === 'coalesced'
          const isQuarantined = status === 'invalid'

          if (isSuccess || isQuarantined) {
            localStorage.setItem('kc.lastUploadT', String(t))

            if (addedId !== undefined) {
              const dbMark = await openDb()
              const txMark = dbMark.transaction(STORE, 'readwrite')
              const osMark = txMark.objectStore(STORE)
              const getReq = osMark.get(addedId)
              getReq.onsuccess = () => {
                const data = getReq.result
                if (data) {
                  if (isSuccess) {
                    data.uploaded = true
                  }
                  if (isQuarantined) {
                    data.quarantined = true
                    data.quarantine = true
                  }
                  osMark.put(data)
                }
              }
              await new Promise<void>((res) => {
                txMark.oncomplete = () => res()
              })
              dbMark.close()
            }
          }
        }
      }
    }
  } catch (err) {
    console.error('Failed to upload signal to Supabase:', err)
  }
}

// Module-level guard: prevent concurrent syncSignalsWithServer calls
let _syncInFlight = false
// Max pings uploaded per sync call — prevents bulk-history floods
const SYNC_CAP = 100

export async function syncSignalsWithServer(uid: string): Promise<void> {
  if (_syncInFlight) return
  _syncInFlight = true
  try {
    const cutoff = Date.now() - 35 * 86_400_000
    const sinceStr = new Date(cutoff).toISOString()

    // 1. Fetch recent server pings (limit to 200 to avoid postgrest cap and save bandwidth)
    const { data: serverData, error } = await supabase
      .from('behavior_pings')
      .select('at, kind')
      .eq('user_id', uid)
      .gte('at', sinceStr)
      .order('at', { ascending: false })
      .limit(200)

    if (error) throw error

    const serverEvents = (serverData ?? []).map(r => ({
      t: new Date(r.at).getTime(),
      kind: r.kind
    }))

    const serverTimestamps = new Set(serverEvents.map(e => e.t))

    // 2. Fetch local signals that need uploading
    const db = await openDb()
    const allPending = await new Promise<Array<{ id: number; t: number; kind: SignalKind; at?: string; uploaded?: boolean; source?: string | null; event_id?: string | null; user_id?: string | null; quarantined?: boolean }>>((resolve, reject) => {
      const tx = db.transaction(STORE, 'readonly')
      const req = tx.objectStore(STORE).getAll()
      req.onsuccess = () => {
        const all = req.result as Array<{ id: number; t: number; kind: SignalKind; at?: string; uploaded?: boolean; source?: string | null; event_id?: string | null; user_id?: string | null; quarantined?: boolean }>
        const pending = all.filter(e => {
          return e.uploaded !== true &&
                 e.quarantined !== true &&
                 e.user_id === uid &&
                 typeof e.event_id === 'string' &&
                 typeof e.source === 'string' &&
                 typeof e.at === 'string' &&
                 Object.values(PING_SOURCES).includes(e.source as any) &&
                 e.t >= cutoff
        })
        resolve(pending)
      }
      req.onerror = () => reject(req.error)
    })
    db.close()

    // Dedupe: skip anything the server already has
    const dedupedPending = allPending.filter(e => !serverTimestamps.has(e.t))

    // Take the most recent SYNC_CAP items (sort descending by t, then slice)
    dedupedPending.sort((a, b) => b.t - a.t)
    const localEventsToUpload = dedupedPending.slice(0, SYNC_CAP)

    // 3. Upload local signals that are missing on the server
    if (localEventsToUpload.length > 0) {
      const events = localEventsToUpload.map(e => {
        return {
          event_id: e.event_id!,
          observed_at: e.at!,
          source: e.source!,
          kind: e.kind
        }
      })

      const { data, error: uploadError } = await supabase.rpc('record_behavior_pings', {
        events
      })
      if (uploadError) throw uploadError

      if (data && Array.isArray(data) && data.length === localEventsToUpload.length) {
        const statuses = data.map((d: any) => d.status || d)

        // Mark these local events as uploaded or quarantined based on responses
        const dbMark = await openDb()
        await new Promise<void>((resolve, reject) => {
          const tx = dbMark.transaction(STORE, 'readwrite')
          const os = tx.objectStore(STORE)
          const getReq = os.getAll()
          getReq.onsuccess = () => {
            const all = getReq.result as Array<{ id: number; t: number; kind: SignalKind; uploaded?: boolean; quarantined?: boolean; quarantine?: boolean }>
            for (const item of all) {
              const idx = localEventsToUpload.findIndex(x => x.id === item.id)
              if (idx !== -1) {
                const status = statuses[idx]
                if (status === 'inserted' || status === 'duplicate' || status === 'coalesced') {
                  item.uploaded = true
                  os.put(item)
                } else if (status === 'invalid') {
                  item.quarantined = true
                  item.quarantine = true
                  os.put(item)
                }
              } else if (item.uploaded === undefined && serverTimestamps.has(item.t)) {
                item.uploaded = true
                os.put(item)
              }
            }
          }
          tx.oncomplete = () => resolve()
          tx.onerror = () => reject(tx.error)
        })
        dbMark.close()
      }
    }

    // 4. Download server pings that are missing locally
    const localEvents = await getAllSignals()
    const localTimestamps = new Set(localEvents.map(e => e.t))
    const toDownload = serverEvents.filter(e => !localTimestamps.has(e.t))
    if (toDownload.length > 0) {
      const dbDl = await openDb()
      await new Promise<void>((resolve, reject) => {
        const tx = dbDl.transaction(STORE, 'readwrite')
        const os = tx.objectStore(STORE)
        for (const se of toDownload) {
          os.add({
            t: se.t,
            at: new Date(se.t).toISOString(),
            kind: se.kind as SignalKind,
            uploaded: true,
            quarantined: false,
            quarantine: false,
            user_id: uid,
            event_id: generateUUID()
          })
        }
        tx.oncomplete = () => resolve()
        tx.onerror = () => reject(tx.error)
      })
      dbDl.close()
    }
  } catch (err) {
    console.error('Failed to sync signals with server:', err)
  } finally {
    _syncInFlight = false
  }
}


export async function getAllSignals(): Promise<SignalEvent[]> {
  const db = await openDb()
  const rows = await new Promise<SignalEvent[]>((resolve, reject) => {
    const tx = db.transaction(STORE, 'readonly')
    const req = tx.objectStore(STORE).getAll()
    req.onsuccess = () =>
      resolve(
        (req.result as Array<{ t: number; kind: SignalKind }>).map((r) => ({
          t: r.t,
          kind: r.kind,
        })),
      )
    req.onerror = () => reject(req.error)
  })
  db.close()
  return rows
}

/** 清理早于 cutoff 的事件（基线只需近若干周；省空间、护隐私） */
export async function pruneBefore(cutoff: number): Promise<void> {
  const db = await openDb()
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(STORE, 'readwrite')
    const idx = tx.objectStore(STORE).index('t')
    const range = IDBKeyRange.upperBound(cutoff, true)
    const req = idx.openCursor(range)
    req.onsuccess = () => {
      const cur = req.result
      if (cur) {
        cur.delete()
        cur.continue()
      }
    }
    tx.oncomplete = () => resolve()
    tx.onerror = () => reject(tx.error)
  })
  db.close()
}
