// 本地行为时序存储（IndexedDB），且当用户登录时支持与 Supabase 双向同步。

import type { SignalEvent, SignalKind } from '@/features/baseline/types'
import { supabase } from '@/lib/supabase'

const DB_NAME = 'keepcontact'
const STORE = 'signals'
const VERSION = 1

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

export async function recordSignal(
  kind: SignalKind,
  t: number = Date.now(),
): Promise<void> {
  const db = await openDb()
  let addedId: number | undefined
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(STORE, 'readwrite')
    const req = tx.objectStore(STORE).add({ t, kind, uploaded: false })
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
      const { data: { session } } = await supabase.auth.getSession()
      if (session?.user?.id) {
        const { error } = await supabase.from('behavior_pings').insert({
          user_id: session.user.id,
          kind,
          at: new Date(t).toISOString(),
        })
        if (!error) {
          localStorage.setItem('kc.lastUploadT', String(t))
          
          if (addedId !== undefined) {
            const dbMark = await openDb()
            const txMark = dbMark.transaction(STORE, 'readwrite')
            const osMark = txMark.objectStore(STORE)
            const getReq = osMark.get(addedId)
            getReq.onsuccess = () => {
              const data = getReq.result
              if (data) {
                data.uploaded = true
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
  } catch (err) {
    console.error('Failed to upload signal to Supabase:', err)
  }
}

export async function syncSignalsWithServer(uid: string): Promise<void> {
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
    
    // 2. Fetch local signals that need uploading (where uploaded !== true)
    const db = await openDb()
    const localEventsToUpload = await new Promise<Array<{ id: number; t: number; kind: SignalKind }>>((resolve, reject) => {
      const tx = db.transaction(STORE, 'readonly')
      const req = tx.objectStore(STORE).getAll()
      req.onsuccess = () => {
        const all = req.result as Array<{ id: number; t: number; kind: SignalKind; uploaded?: boolean }>
        const pending = all.filter(e => e.uploaded !== true && e.t >= cutoff)
        resolve(pending)
      }
      req.onerror = () => reject(req.error)
    })
    db.close()

    // 3. Upload local signals that are missing on the server
    if (localEventsToUpload.length > 0) {
      const inserts = localEventsToUpload.map(e => ({
        user_id: uid,
        kind: e.kind,
        at: new Date(e.t).toISOString()
      }))
      const { error: uploadError } = await supabase
        .from('behavior_pings')
        .insert(inserts)
        
      if (uploadError) throw uploadError

      // Mark these local events as uploaded
      const dbMark = await openDb()
      await new Promise<void>((resolve, reject) => {
        const tx = dbMark.transaction(STORE, 'readwrite')
        const os = tx.objectStore(STORE)
        const getReq = os.getAll()
        getReq.onsuccess = () => {
          const all = getReq.result as Array<{ id: number; t: number; kind: SignalKind; uploaded?: boolean }>
          for (const item of all) {
            let changed = false
            if (localEventsToUpload.some(x => x.id === item.id)) {
              item.uploaded = true
              changed = true
            } else if (item.uploaded === undefined && serverTimestamps.has(item.t)) {
              item.uploaded = true
              changed = true
            }
            if (changed) {
              os.put(item)
            }
          }
        }
        tx.oncomplete = () => resolve()
        tx.onerror = () => reject(tx.error)
      })
      dbMark.close()
    }
    
    // 4. Download server signals that are missing locally
    const localEvents = await getAllSignals()
    const localTimestamps = new Set(localEvents.map(e => e.t))
    const toDownload = serverEvents.filter(e => !localTimestamps.has(e.t))
    if (toDownload.length > 0) {
      const dbDl = await openDb()
      await new Promise<void>((resolve, reject) => {
        const tx = dbDl.transaction(STORE, 'readwrite')
        const os = tx.objectStore(STORE)
        for (const se of toDownload) {
          os.add({ t: se.t, kind: se.kind as SignalKind, uploaded: true })
        }
        tx.oncomplete = () => resolve()
        tx.onerror = () => reject(tx.error)
      })
      dbDl.close()
    }
  } catch (err) {
    console.error('Failed to sync signals with server:', err)
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
