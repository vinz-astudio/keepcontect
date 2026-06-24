import { useEffect, useRef } from 'react'
import QRCode from 'qrcode'
import { useI18n } from '@/lib/i18n'

interface QRModalProps {
  url: string
  title: string
  onClose: () => void
}

export function QRModal({ url, title, onClose }: QRModalProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const { t } = useI18n()

  useEffect(() => {
    if (canvasRef.current) {
      QRCode.toCanvas(canvasRef.current, url, {
        width: 240,
        margin: 2,
        color: {
          dark: '#000000',
          light: '#ffffff',
        },
      }).catch(console.error)
    }
  }, [url])

  return (
    <div
      style={{
        position: 'fixed',
        inset: 0,
        zIndex: 1000,
        background: 'rgba(0,0,0,0.55)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        padding: '1.5rem',
      }}
      onClick={onClose}
    >
      <div
        style={{
          background: 'var(--bg)',
          borderRadius: 'var(--r-lg)',
          padding: '1.5rem',
          maxWidth: '320px',
          width: '100%',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          gap: '1rem',
          boxShadow: '0 8px 32px rgba(0,0,0,0.25)',
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <h3 style={{ margin: 0, fontSize: '1rem', fontWeight: '600', textAlign: 'center' }}>
          {t('qr.title')} · {title}
        </h3>

        <div
          style={{
            background: '#fff',
            borderRadius: 'var(--r-md)',
            padding: '12px',
            display: 'inline-flex',
          }}
        >
          <canvas ref={canvasRef} />
        </div>

        <p style={{ margin: 0, fontSize: '0.78rem', color: 'var(--fg-muted)', textAlign: 'center' }}>
          {t('qr.expire')}
        </p>

        <button
          onClick={onClose}
          style={{
            width: '100%',
            padding: '10px',
            background: 'var(--bg-soft)',
            border: '1px solid var(--line)',
            borderRadius: 'var(--r-md)',
            cursor: 'pointer',
            color: 'var(--fg)',
            fontWeight: '600',
          }}
        >
          {t('profile.scan.cancel')}
        </button>
      </div>
    </div>
  )
}
