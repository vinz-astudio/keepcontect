import { getAutomaticPingSource } from './api'
import { createPwaEvidenceCollector } from './pwaEvidence'
import { bindPassiveCollector, recordAuthenticatedPassiveEvidence, revokePassiveCollector } from './evidenceContract'
import { isSensorEnabled } from '@/features/signals/sensors'
import { supabase } from '@/lib/supabase'
import { Capacitor } from '@capacitor/core'
import { isTauri } from '@/lib/platform'

export function startPwaPassiveEvidence(ownerId: string | null): () => void {
  if (!ownerId || Capacitor.isNativePlatform() || isTauri() || getAutomaticPingSource() !== 'installed_pwa') return () => {}
  const collector = createPwaEvidenceCollector(ownerId, {
    eligible: () => getAutomaticPingSource() === 'installed_pwa' && isSensorEnabled('interaction'),
    visible: () => document.visibilityState === 'visible',
    getUserId: async () => (await supabase.auth.getSession()).data.session?.user.id ?? null,
    now: Date.now, randomUUID: () => crypto.randomUUID(), instanceId: `pwa-${crypto.randomUUID()}`,
    bind: bindPassiveCollector, send: recordAuthenticatedPassiveEvidence, revoke: revokePassiveCollector,
  })
  const onInteraction = (event: Event) => {
    if (event instanceof KeyboardEvent && event.repeat) return
    void collector.interaction(event.isTrusted)
  }
  const retry = () => { void collector.retry() }
  document.addEventListener('pointerdown', onInteraction)
  document.addEventListener('keydown', onInteraction)
  window.addEventListener('online', retry)
  const timer = window.setInterval(retry, 30_000)
  return () => {
    document.removeEventListener('pointerdown', onInteraction)
    document.removeEventListener('keydown', onInteraction)
    window.removeEventListener('online', retry)
    window.clearInterval(timer)
    collector.stop()
  }
}
