import { describe, expect, it, vi } from 'vitest'
import { createNotificationActionDrainer, type NotificationAction } from './notificationActions'
const action: NotificationAction = { contractVersion: 2, eventId:'old:safe',notificationId:'old',alertId:'alert-old',recipientUserId:'owner',kind:'self',action:'acknowledge_safe',generation:3 }
function setup(actions: NotificationAction[]=[action]) {
  const deps = { owner:'owner',generation:3,isCurrent:()=>true,list:vi.fn(async()=>actions),complete:vi.fn(async()=>{}),acknowledge:vi.fn(async()=>{}),open:vi.fn(),confirmed:vi.fn(async()=>{}),failed:vi.fn() }
  return { deps, drain:createNotificationActionDrainer(deps) }
}
describe('native notification action drain',()=>{
  it('a permanently deleted notification cannot block a later valid action',async()=>{
    const next={...action,eventId:'new:safe',notificationId:'new',alertId:'alert-new'}
    const {deps,drain}=setup([action,next])
    deps.acknowledge.mockRejectedValueOnce({message:'notification_not_owned'})
    await drain()
    expect(deps.complete).toHaveBeenCalledWith(action)
    expect(deps.acknowledge).toHaveBeenLastCalledWith('new','alert-new')
    expect(deps.confirmed).toHaveBeenCalledOnce()
  })
  it('confirms the original alert then completes without generating a new check-in',async()=>{
    const {deps,drain}=setup(); await drain()
    expect(deps.acknowledge).toHaveBeenCalledWith('old','alert-old')
    expect(deps.complete).toHaveBeenCalledWith(action)
    expect(deps.confirmed).toHaveBeenCalledOnce()
  })
  it('retains a failed request for resume/online retry',async()=>{
    const {deps,drain}=setup(); deps.acknowledge.mockRejectedValueOnce(Error('offline'))
    await drain(); expect(deps.complete).not.toHaveBeenCalled()
    await drain(); expect(deps.acknowledge).toHaveBeenCalledTimes(2); expect(deps.complete).toHaveBeenCalledOnce()
  })
  it('ignores a different owner and a previous login generation',async()=>{
    const {deps,drain}=setup([{...action,recipientUserId:'other'},{...action,generation:2}]); await drain()
    expect(deps.acknowledge).not.toHaveBeenCalled(); expect(deps.complete).not.toHaveBeenCalled()
  })
  it('serializes concurrent warm and cold triggers and stops after owner change',async()=>{
    const {deps,drain}=setup(); let release!:()=>void; let current=true
    deps.isCurrent=()=>current
    deps.acknowledge.mockImplementationOnce(()=>new Promise<void>(r=>{release=r}))
    const pending=drain(); await Promise.resolve(); await drain()
    expect(deps.acknowledge).toHaveBeenCalledOnce(); current=false; release(); await pending
    expect(deps.complete).not.toHaveBeenCalled(); expect(deps.confirmed).not.toHaveBeenCalled()
  })
  it('opens body taps without acknowledging, and rejects unscoped legacy actions',async()=>{
    const {deps,drain}=setup([{...action,action:'open'},{...action,alertId:undefined}]); await drain()
    expect(deps.open).toHaveBeenCalledWith('self'); expect(deps.acknowledge).not.toHaveBeenCalled()
  })
})
