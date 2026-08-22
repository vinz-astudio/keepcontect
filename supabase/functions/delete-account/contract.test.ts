import { describe, it, expect, vi, beforeEach } from 'vitest'
import { readFileSync, existsSync, readdirSync } from 'node:fs'
import { join } from 'node:path'
import { deleteMyAccount } from '@/features/profile/profileApi'
import { supabase } from '@/lib/supabase'
import * as signalStore from '@/features/signals/store'

describe('delete-account & purge_user_data schema contract', () => {
  const rootDir = process.cwd()
  const migrationsDir = join(rootDir, 'supabase/migrations')
  const migrationPath = join(migrationsDir, '20260821060000_purge_user_data.sql')
  const edgeFunctionPath = join(rootDir, 'supabase/functions/delete-account/index.ts')

  it('verifies that purge_user_data SQL migration exists and adds ios_url column', () => {
    expect(existsSync(migrationPath)).toBe(true)
    const sql = readFileSync(migrationPath, 'utf8')
    expect(sql).toContain('ALTER TABLE public.app_versions ADD COLUMN IF NOT EXISTS ios_url text;')
    expect(sql).toContain('CREATE OR REPLACE FUNCTION public.purge_user_data(target_user_id uuid)')
  })

  it('ensures all tables and filtered columns referenced in purge_user_data exist in migrations schema with exact schema qualifiers', () => {
    const purgeSql = readFileSync(migrationPath, 'utf8')

    // Concatenate all migration SQL files to form the full schema
    const migrationFiles = readdirSync(migrationsDir).filter((f) => f.endsWith('.sql'))
    const allSchemaSql = migrationFiles
      .map((f) => readFileSync(join(migrationsDir, f), 'utf8'))
      .join('\n')

    // Prohibited bad legacy references
    const prohibitedTables = ['guardians', 'alert_signals', 'routine_history', 'checkin_snoozes']
    for (const badTable of prohibitedTables) {
      const regex = new RegExp(`(?:public|private)\\.${badTable}\\b`, 'i')
      expect(regex.test(purgeSql), `purge_user_data should not reference non-existent table: ${badTable}`).toBe(false)
    }

    // Prohibited non-user tables
    const nonUserTables = ['alert_judgment_evaluations', 'routine_mode_cohort_generations', 'routine_mode_cohort_invalidations', 'routine_mode_cohort_priors']
    for (const badTable of nonUserTables) {
      const regex = new RegExp(`(?:public|private)\\.${badTable}\\b`, 'i')
      expect(regex.test(purgeSql), `purge_user_data should not delete from non-user table: ${badTable}`).toBe(false)
    }

    // Build map of actual table schemas (public vs private) across all migrations
    const schemaTableMap = new Map<string, string>()
    const tableRegex = /CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:["']?(public|private)["']?\.)?["']?([a-z0-9_]+)["']?\s*\(/gi
    let tMatch: RegExpExecArray | null
    while ((tMatch = tableRegex.exec(allSchemaSql)) !== null) {
      const schema = (tMatch[1] || 'public').toLowerCase()
      const table = tMatch[2].toLowerCase()
      schemaTableMap.set(table, schema)
    }

    // Verify every referenced table exists and has exact matching schema qualifier (public vs private)
    const refRegex = /(public|private)\.([a-z0-9_]+)/gi
    let rMatch: RegExpExecArray | null
    while ((rMatch = refRegex.exec(purgeSql)) !== null) {
      const declaredSchema = rMatch[1].toLowerCase()
      const table = rMatch[2].toLowerCase()
      if (table === 'purge_user_data' || table === 'app_versions') continue
      const actualSchema = schemaTableMap.get(table)
      expect(actualSchema, `Table ${table} must exist in migration schema`).toBeDefined()
      expect(declaredSchema, `Schema for table ${table} must match schema in migration`).toBe(actualSchema)
    }

    // Check critical foreign keys and columns strictly within each table's own CREATE TABLE definition
    const explicitColumnChecks = [
      { table: 'alerts', col: 'paused_by' },
      { table: 'alerts', col: 'resolved_by' },
      { table: 'alerts', col: 'user_id' },
      { table: 'gm_mutes', col: 'user_id' },
      { table: 'gm_mutes', col: 'muted_by' },
      { table: 'alert_events', col: 'actor_id' },
      { table: 'job_failures', col: 'subject_id' },
      { table: 'passive_window_transitions', col: 'user_id' },
      { table: 'passive_evidence_events', col: 'user_id' },
      { table: 'passive_evidence_incidents', col: 'user_id' },
      { table: 'passive_surface_health_intervals', col: 'user_id' },
      { table: 'passive_collector_bindings', col: 'user_id' },
      { table: 'passive_shadow_candidates', col: 'user_id' },
      { table: 'passive_checkin_recommendations', col: 'user_id' },
      { table: 'passive_checkin_accounts', col: 'user_id' },
      { table: 'passive_checkin_accounts', col: 'active_contract_version_id' },
      { table: 'passive_checkin_accounts', col: 'active_epoch_id' },
      { table: 'passive_checkin_windows', col: 'user_id' },
      { table: 'passive_monitoring_epochs', col: 'user_id' },
      { table: 'passive_checkin_contract_versions', col: 'user_id' },
      { table: 'passive_checkin_contract_versions', col: 'created_by' },
      { table: 'guardianships', col: 'ward_id' },
      { table: 'guardianships', col: 'guardian_id' },
      { table: 'guardianships', col: 'status' },
      { table: 'group_members', col: 'user_id' },
      { table: 'community_members', col: 'user_id' },
      { table: 'groups', col: 'created_by' },
      { table: 'communities', col: 'created_by' },
      { table: 'special_attention_subscriptions', col: 'subscriber_id' },
      { table: 'special_attention_subscriptions', col: 'subject_id' },
      { table: 'special_attention_notices', col: 'subscriber_id' },
      { table: 'protection_health_incidents', col: 'user_id' },
      { table: 'checkin_tasks', col: 'ward_id' },
      { table: 'checkin_tasks', col: 'created_by' },
      { table: 'notifications', col: 'recipient_id' },
      { table: 'clients', col: 'user_id' },
      { table: 'heartbeat_tokens', col: 'user_id' },
      { table: 'push_tokens', col: 'user_id' },
      { table: 'push_subscriptions', col: 'user_id' },
      { table: 'app_admins', col: 'user_id' },
      { table: 'alert_shadow_coverage_leases', col: 'user_id' },
      { table: 'adaptive_alert_shadow_profile_dirty', col: 'user_id' },
      { table: 'adaptive_alert_shadow_subject_context_state', col: 'user_id' },
      { table: 'adaptive_alert_shadow_user_state', col: 'user_id' },
      { table: 'behavior_pings', col: 'user_id' },
      { table: 'device_activity_samples', col: 'user_id' },
      { table: 'daily_activity_aggregates', col: 'user_id' },
      { table: 'account_gap_profiles', col: 'user_id' },
      { table: 'account_normal_bounds', col: 'user_id' },
      { table: 'account_threshold_shadow', col: 'user_id' },
      { table: 'alert_gap_profiles', col: 'user_id' },
      { table: 'alert_intervention_events', col: 'user_id' },
      { table: 'alert_judgment_shadow_decisions', col: 'user_id' },
      { table: 'alert_judgment_subject_contexts', col: 'user_id' },
      { table: 'alert_observation_coverage_intervals', col: 'user_id' },
      { table: 'alert_sleep_night_contexts', col: 'user_id' },
      { table: 'emergency_info', col: 'user_id' },
      { table: 'device_state', col: 'user_id' },
      { table: 'user_activity_profiles', col: 'user_id' },
      { table: 'user_settings', col: 'user_id' },
      { table: 'profiles', col: 'id' }
    ]

    for (const check of explicitColumnChecks) {
      const tableBlockRegex = new RegExp(`CREATE TABLE (?:IF NOT EXISTS )?(?:"?(?:public|private)"?\\.)?"?${check.table}"?\\s*\\(([\\s\\S]*?)\\);`, 'i')
      const blockMatch = allSchemaSql.match(tableBlockRegex)
      expect(blockMatch, `Table ${check.table} definition must exist`).toBeDefined()
      const tableBody = blockMatch ? blockMatch[1] : ''
      const colRegex = new RegExp(`"?${check.col}"?\\s+`, 'i')
      expect(colRegex.test(tableBody), `Column ${check.col} must exist inside table ${check.table} definition`).toBe(true)
    }
  })

  it('verifies foreign key un-linking on alerts, gm_mutes, and passive_checkin contract versions cascade', () => {
    const purgeSql = readFileSync(migrationPath, 'utf8')
    expect(purgeSql).toContain('ALTER TABLE public.passive_checkin_contract_versions')
    expect(purgeSql).toContain('ON DELETE CASCADE')
    expect(purgeSql).toContain('UPDATE public.alerts SET paused_by = NULL WHERE paused_by = target_user_id;')
    expect(purgeSql).toContain('UPDATE public.alerts SET resolved_by = NULL WHERE resolved_by = target_user_id;')
    expect(purgeSql).toContain('DELETE FROM public.gm_mutes WHERE user_id = target_user_id OR muted_by = target_user_id;')
    expect(purgeSql).toContain('UPDATE public.passive_checkin_accounts')
    expect(purgeSql).toContain('DELETE FROM public.passive_checkin_contract_versions WHERE user_id = target_user_id;')
    expect(purgeSql).toContain("DELETE FROM public.notifications WHERE recipient_id = target_user_id OR (params->>'subject_id')::text = target_user_id::text;")
    expect(purgeSql).toContain('DELETE FROM public.special_attention_notices')
    expect(purgeSql).toContain('incident_id IN (SELECT id FROM public.protection_health_incidents WHERE user_id = target_user_id)')
  })



  it('verifies delete-account edge function contract, fail-closed handling and durable tombstone fallback', () => {
    expect(existsSync(edgeFunctionPath)).toBe(true)
    const code = readFileSync(edgeFunctionPath, 'utf8')
    expect(code).toContain("supabaseAdmin.rpc('purge_user_data'")
    expect(code).toContain("supabaseAdmin.auth.admin.deleteUser(uid)")
    expect(code).toContain("attempt <= 3")
    expect(code).toContain("updateUserById(uid")
    expect(code).toContain("ban_duration: '87660000h'")
    expect(code).toContain("email: tombstoneEmail")
    expect(code).toContain("account_deleted_at")
    expect(code).toContain("status: 401")
    expect(code).toContain("Missing Authorization header")
    expect(code).toContain("Invalid user token")
    expect(code).toContain("tombstone: true")
  })

  describe('deleteMyAccount behavioral unit test suite', () => {
    const mockStorage = new Map<string, string>()
    let mockInvoke: any
    let clearSignalsSpy: any

    beforeEach(() => {
      vi.clearAllMocks()
      mockStorage.clear()
      globalThis.localStorage = {
        getItem: (k: string) => mockStorage.get(k) ?? null,
        setItem: (k: string, v: string) => mockStorage.set(k, String(v)),
        removeItem: (k: string) => mockStorage.delete(k),
        clear: () => mockStorage.clear(),
        length: mockStorage.size,
        key: (_idx: number) => null,
      } as any

      mockInvoke = vi.fn()
      Object.defineProperty(supabase, 'functions', {
        value: { invoke: mockInvoke },
        configurable: true,
        writable: true,
      })

      clearSignalsSpy = vi.spyOn(signalStore, 'clearLocalSignalStore').mockResolvedValue()
    })

    it('completes client cleanup in strict sequence (invoke -> clear storage -> clear indexeddb -> signOut)', async () => {
      const callSequence: string[] = []

      localStorage.setItem('kc_token', 'test_token')
      vi.spyOn(supabase.auth, 'getSession').mockResolvedValue({
        data: { session: { user: { id: 'u1', email: 'user@example.com' } } },
        error: null,
      } as any)

      mockInvoke.mockImplementation(async () => {
        callSequence.push('invoke')
        return { data: { ok: true, deletedUserId: 'u1' }, error: null }
      })

      const origClear = localStorage.clear
      localStorage.clear = () => {
        callSequence.push('localStorage.clear')
        origClear.call(localStorage)
      }

      clearSignalsSpy.mockImplementation(async () => {
        callSequence.push('clearLocalSignalStore')
      })

      vi.spyOn(supabase.auth, 'signOut').mockImplementation(async () => {
        callSequence.push('signOut')
        return { error: null } as any
      })

      await deleteMyAccount()

      expect(callSequence).toEqual(['invoke', 'localStorage.clear', 'clearLocalSignalStore', 'signOut'])
      expect(localStorage.getItem('kc_token')).toBeNull()
    })

    it('fails closed and does not call signOut if clearLocalSignalStore fails', async () => {
      vi.spyOn(supabase.auth, 'getSession').mockResolvedValue({
        data: { session: { user: { id: 'u1', email: 'user@example.com' } } },
        error: null,
      } as any)

      mockInvoke.mockResolvedValue({
        data: { ok: true, deletedUserId: 'u1' },
        error: null,
      })

      clearSignalsSpy.mockRejectedValue(new Error('IndexedDB deletion failed'))
      const signOutSpy = vi.spyOn(supabase.auth, 'signOut')

      await expect(deleteMyAccount()).rejects.toThrow('IndexedDB deletion failed')
      expect(signOutSpy).not.toHaveBeenCalled()
    })

    it('fails closed and aborts before IndexedDB cleanup or signOut if localStorage.clear throws', async () => {
      vi.spyOn(supabase.auth, 'getSession').mockResolvedValue({
        data: { session: { user: { id: 'u1', email: 'user@example.com' } } },
        error: null,
      } as any)

      mockInvoke.mockResolvedValue({
        data: { ok: true, deletedUserId: 'u1' },
        error: null,
      })

      localStorage.clear = () => {
        throw new Error('localStorage write-protected')
      }

      const signOutSpy = vi.spyOn(supabase.auth, 'signOut')

      await expect(deleteMyAccount()).rejects.toThrow('本地存储清理失败: localStorage write-protected')
      expect(clearSignalsSpy).not.toHaveBeenCalled()
      expect(signOutSpy).not.toHaveBeenCalled()
    })

    it('fails closed and preserves state if edge function returns an error', async () => {
      localStorage.setItem('kc_critical_data', 'keep_me')
      vi.spyOn(supabase.auth, 'getSession').mockResolvedValue({
        data: { session: { user: { id: 'u1', email: 'user@example.com' } } },
        error: null,
      } as any)

      mockInvoke.mockResolvedValue({
        data: { ok: false, error: 'Database purge failed: foreign key' },
        error: null,
      })

      const signOutSpy = vi.spyOn(supabase.auth, 'signOut')

      await expect(deleteMyAccount()).rejects.toThrow('Database purge failed')
      expect(localStorage.getItem('kc_critical_data')).toBe('keep_me')
      expect(clearSignalsSpy).not.toHaveBeenCalled()
      expect(signOutSpy).not.toHaveBeenCalled()
    })
  })

  describe('clearLocalSignalStore fail-closed behavior', () => {
    beforeEach(() => {
      vi.restoreAllMocks()
    })

    it('resolves on successful deleteDatabase request', async () => {
      const mockReq = {
        onsuccess: null as any,
        onerror: null as any,
        onblocked: null as any,
      }
      globalThis.indexedDB = {
        deleteDatabase: vi.fn(() => {
          setTimeout(() => mockReq.onsuccess?.(), 5)
          return mockReq
        }),
      } as any

      await expect(signalStore.clearLocalSignalStore()).resolves.toBeUndefined()
    })

    it('rejects fail-closed on deleteDatabase error event', async () => {
      const mockReq = {
        onsuccess: null as any,
        onerror: null as any,
        onblocked: null as any,
        error: new Error('IDB delete error'),
      }
      globalThis.indexedDB = {
        deleteDatabase: vi.fn(() => {
          setTimeout(() => mockReq.onerror?.(), 5)
          return mockReq
        }),
      } as any

      await expect(signalStore.clearLocalSignalStore()).rejects.toThrow('IDB delete error')
    })

    it('rejects fail-closed on persistent deleteDatabase onblocked event', async () => {
      const mockInitialReq = {
        onsuccess: null as any,
        onerror: null as any,
        onblocked: null as any,
      }
      const mockRetryReq = {
        onsuccess: null as any,
        onerror: null as any,
        onblocked: null as any,
      }

      let callCount = 0
      globalThis.indexedDB = {
        deleteDatabase: vi.fn(() => {
          callCount++
          if (callCount === 1) {
            setTimeout(() => mockInitialReq.onblocked?.(), 5)
            return mockInitialReq
          } else {
            setTimeout(() => mockRetryReq.onblocked?.(), 5)
            return mockRetryReq
          }
        }),
      } as any

      await expect(signalStore.clearLocalSignalStore()).rejects.toThrow('persistently blocked')
    })
  })
})
