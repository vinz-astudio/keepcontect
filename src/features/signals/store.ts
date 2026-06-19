// 本地行为时序存储（IndexedDB）——绝不上传，仅供端上判定/基线使用。

import type { SignalEvent, SignalKind } from '@/features/baseline/types'

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
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(STORE, 'readwrite')
    tx.objectStore(STORE).add({ t, kind })
    tx.oncomplete = () => resolve()
    tx.onerror = () => reject(tx.error)
  })
  db.close()
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
