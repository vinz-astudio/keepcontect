export interface PushBinding {
  bindingId: string
  ownerId: string
  generation: number
  secret: string
  token?: string
}
export interface PushBindingState {
  installationId: string
  generation: number
  active: PushBinding | null
  pending: PushBinding[]
}
export const PUSH_BINDING_KEY = 'kc.push.bindingState.v2'

export function readPushBindingState(storage: Pick<Storage,'getItem'>, uuid: () => string): PushBindingState {
  try {
    const state = JSON.parse(storage.getItem(PUSH_BINDING_KEY) ?? 'null') as PushBindingState | null
    if (state && typeof state.installationId === 'string' && Number.isSafeInteger(state.generation) && Array.isArray(state.pending)) return state
  } catch { /* First install or corrupt local state: no account session is inferred. */ }
  return { installationId: uuid(), generation: 0, active: null, pending: [] }
}
export function activatePushBinding(state: PushBindingState, owner: string, uuid: () => string, secret: () => string): PushBinding {
  if (state.active?.ownerId === owner) return state.active
  retirePushBinding(state)
  const binding = {bindingId:uuid(),ownerId:owner,generation:++state.generation,secret:secret()}
  state.active=binding
  return binding
}
export function retirePushBinding(state: PushBindingState): void {
  if (state.active && !state.pending.some(row=>row.bindingId===state.active!.bindingId)) state.pending.push(state.active)
  state.active=null
}
