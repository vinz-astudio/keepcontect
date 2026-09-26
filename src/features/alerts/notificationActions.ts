export interface NotificationAction {
  eventId: string
  notificationId: string
  alertId?: string
  recipientUserId: string
  kind: string
  action: 'open' | 'acknowledge_safe'
  contractVersion: 2
  generation: string | number
}

interface ActionDeps {
  owner: string
  generation: string | number
  isCurrent(): boolean
  list(): Promise<NotificationAction[]>
  complete(action: NotificationAction): Promise<void>
  acknowledge(notificationId: string, alertId: string): Promise<void>
  open(kind: string): void
  confirmed(): Promise<void>
  failed(error: unknown): void
}

/** Reads are non-destructive. Only an accepted action gets a durable completion. */
export function createNotificationActionDrainer(deps: ActionDeps) {
  let inFlight = false
  return async () => {
    if (inFlight || !deps.isCurrent()) return
    inFlight = true
    try {
      for (const action of await deps.list()) {
        if (!deps.isCurrent()) return
        if (action.recipientUserId !== deps.owner || action.generation !== deps.generation) continue
        if (action.contractVersion !== 2 || !action.eventId || !action.notificationId) continue
        try {
        if (action.action === 'acknowledge_safe') {
          if (!action.alertId || !['self', 'concern'].includes(action.kind)) continue
          await deps.acknowledge(action.notificationId, action.alertId)
          if (!deps.isCurrent()) return
          await deps.complete(action)
          if (deps.isCurrent()) await deps.confirmed()
        } else if (action.action === 'open') {
          deps.open(action.kind)
          await deps.complete(action)
        }
        } catch (error) {
          if (!deps.isCurrent()) return
          const message = error instanceof Error ? error.message : String((error as {message?:string})?.message ?? '')
          if (/notification_not_owned|notification_alert_mismatch|alert_id_required/.test(message)) {
            await deps.complete(action)
          } else if (message.includes('pattern_required')) {
            deps.open(action.kind)
          }
          deps.failed(error)
        }
      }
    } catch (error) {
      // Retain on offline/permission failure. The server's exact-ID operation is
      // idempotent if the process dies after acknowledgement and before completion.
      if (deps.isCurrent()) deps.failed(error)
    } finally { inFlight = false }
  }
}
