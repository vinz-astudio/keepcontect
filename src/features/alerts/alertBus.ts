// 本机告警事件总线：任一界面执行了「确认安全/报平安/认领」等改变告警状态的操作后，
// 立即通知其它界面(如 StatusBoard 平安看板)同步刷新，不必等 60s 轮询或 realtime。
type Listener = () => void

const listeners = new Set<Listener>()

/** 订阅本机告警变更；返回取消订阅函数 */
export function onAlertChange(cb: Listener): () => void {
  listeners.add(cb)
  return () => {
    listeners.delete(cb)
  }
}

/** 广播：告警状态已变更，相关界面应刷新 */
export function emitAlertChange(): void {
  for (const cb of [...listeners]) {
    try {
      cb()
    } catch {
      /* 单个订阅者出错不影响其它 */
    }
  }
}
