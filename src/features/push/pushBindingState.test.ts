import { describe, expect, it } from 'vitest'
import { activatePushBinding, retirePushBinding, readPushBindingState } from './pushBindingState'
describe('offline push binding identity',()=>{
  it('retains only a revoke capability when signing out before registration finishes',()=>{
    const state=readPushBindingState({getItem:()=>null},()=> 'install')
    activatePushBinding(state,'A',()=> 'binding-A',()=> 'secret-A'); retirePushBinding(state)
    expect(state.active).toBeNull(); expect(state.pending).toHaveLength(1)
    expect(JSON.stringify(state)).not.toMatch(/refresh_token|access_token/)
    activatePushBinding(state,'B',()=> 'binding-B',()=> 'secret-B')
    expect(state.active).toMatchObject({ownerId:'B',generation:2})
    expect(state.pending[0]).toMatchObject({bindingId:'binding-A',ownerId:'A'})
  })
  it('preserves a same-owner cold restart but rotates A→B→A',()=>{
    const state=readPushBindingState({getItem:()=>null},()=> 'install')
    const initial=activatePushBinding(state,'A',()=> 'A1',()=> 'cap')
    const restored=readPushBindingState({getItem:()=>JSON.stringify(state)},()=> 'unused')
    expect(activatePushBinding(restored,'A',()=> 'unused',()=> 'unused')).toEqual(initial)
    activatePushBinding(restored,'B',()=> 'B1',()=> 'cap')
    expect(activatePushBinding(restored,'A',()=> 'A2',()=> 'cap').bindingId).toBe('A2')
    expect(restored.pending.map(row=>row.bindingId)).toEqual(['A1','B1'])
  })
})
