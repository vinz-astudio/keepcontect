import { supabase } from '@/lib/supabase'

export const PASSIVE_QUALIFICATION_POLICY = 'passive-qualification-v1' as const
export type PassiveSurfaceType =
  | 'tauri_native'
  | 'tauri_native_linux'
  | 'android_native'
  | 'ios_native'
  | 'pwa_browser'
  | 'shortcut'
export type PassiveEvidenceClass =
  | 'direct_device_use'
  | 'personal_device_motion'
  | 'power_transition'
  | 'explicit_self_activity'

export const COLLECTOR_CONTRACTS: Record<PassiveSurfaceType, string> = {
  tauri_native: 'tauri-passive-evidence-v1',
  tauri_native_linux: 'tauri-linux-foreground-v1',
  android_native: 'android-passive-evidence-v1',
  ios_native: 'ios-passive-evidence-v1',
  pwa_browser: 'pwa-interaction-v1',
  shortcut: 'shortcut-app-open-v1',
}

export interface PassiveCollectorBinding {
  bindingId: string
  credential: string
  credentialVersion: number
  surfaceType: PassiveSurfaceType
  collectorContract: string
}

export interface PassiveEvidenceDraft {
  eventId: string
  sequence: number
  observedAt: string
  evidenceClass: PassiveEvidenceClass
  correlationId: string | null
  qualificationFacts: Record<string, boolean | number | string>
  queryStartedAt?: string | null
  queryEndedAt?: string | null
  querySucceeded?: boolean
}

function record(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null
}

export function parsePassiveCollectorBinding(value: unknown): PassiveCollectorBinding {
  const raw = record(value)
  const surfaceType = raw?.surface_type
  if (
    !raw
    || typeof raw.binding_id !== 'string'
    || typeof raw.credential !== 'string'
    || raw.credential.length < 32
    || !Number.isSafeInteger(raw.credential_version)
    || typeof surfaceType !== 'string'
    || !(surfaceType in COLLECTOR_CONTRACTS)
    || raw.collector_contract !== COLLECTOR_CONTRACTS[surfaceType as PassiveSurfaceType]
  ) throw new Error('Invalid passive collector binding')
  return {
    bindingId: raw.binding_id,
    credential: raw.credential,
    credentialVersion: raw.credential_version as number,
    surfaceType: surfaceType as PassiveSurfaceType,
    collectorContract: raw.collector_contract,
  }
}

export function buildPassiveEvidenceRequest(binding: PassiveCollectorBinding, draft: PassiveEvidenceDraft) {
  if (!Number.isSafeInteger(draft.sequence) || draft.sequence < 0 || Number.isNaN(Date.parse(draft.observedAt))) {
    throw new Error('Invalid passive evidence draft')
  }
  return {
    binding_id: binding.bindingId,
    credential: binding.credential,
    event_id: draft.eventId,
    sequence: draft.sequence,
    observed_at: new Date(draft.observedAt).toISOString(),
    evidence_class: draft.evidenceClass,
    qualification_policy_version: PASSIVE_QUALIFICATION_POLICY,
    correlation_id: draft.correlationId,
    qualification_facts: draft.qualificationFacts,
    query_started_at: draft.queryStartedAt ?? null,
    query_ended_at: draft.queryEndedAt ?? null,
    query_succeeded: draft.querySucceeded ?? false,
  }
}

export async function bindPassiveCollector(
  collectorInstanceId: string,
  surfaceType: PassiveSurfaceType,
  clientVersion: string,
): Promise<PassiveCollectorBinding> {
  const { data, error } = await supabase.rpc('bind_passive_collector', {
    _collector_instance_id: collectorInstanceId,
    _surface_type: surfaceType,
    _collector_contract: COLLECTOR_CONTRACTS[surfaceType],
    _client_version: clientVersion,
  })
  if (error) throw error
  return parsePassiveCollectorBinding(data)
}

export async function revokePassiveCollector(bindingId: string): Promise<boolean> {
  const { data, error } = await supabase.rpc('revoke_passive_collector', { _binding_id: bindingId })
  if (error) throw error
  return data
}

export async function recordAuthenticatedPassiveEvidence(
  bindingId: string,
  draft: PassiveEvidenceDraft,
): Promise<string> {
  const { data, error } = await supabase.rpc('record_authenticated_passive_evidence', {
    _binding_id: bindingId,
    _event_id: draft.eventId,
    _sequence: draft.sequence,
    _observed_at: draft.observedAt,
    _evidence_class: draft.evidenceClass,
    _qualification_policy_version: PASSIVE_QUALIFICATION_POLICY,
    _correlation_id: draft.correlationId,
    _qualification_facts: draft.qualificationFacts,
  })
  if (error) throw error
  return data
}
