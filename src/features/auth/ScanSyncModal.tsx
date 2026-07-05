import { useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import jsQR from 'jsqr'
import { useI18n } from '@/lib/i18n'
import './ScanSyncModal.css'

interface Props {
  onClose: () => void
  onScan: (data: string) => void
  title?: string
  hint?: string
}

export function ScanSyncModal({ onClose, onScan, title, hint }: Props) {
  const { t } = useI18n()
  const videoRef = useRef<HTMLVideoElement>(null)
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const [error, setError] = useState<string | null>(null)
  const streamRef = useRef<MediaStream | null>(null)

  useEffect(() => {
    let active = true

    async function startCamera() {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: 'environment' }
        })
        if (!active) {
          stream.getTracks().forEach((track) => track.stop())
          return
        }
        streamRef.current = stream
        if (videoRef.current) {
          videoRef.current.srcObject = stream
          videoRef.current.setAttribute('playsinline', 'true') // iOS Safari compatibility
          videoRef.current.play().catch(() => {})
        }
      } catch (err) {
        console.error('Camera access failed:', err)
        setError(t('profile.scan.cameraError'))
      }
    }

    void startCamera()

    return () => {
      active = false
      if (streamRef.current) {
        streamRef.current.getTracks().forEach((track) => track.stop())
      }
    }
  }, [t])

  useEffect(() => {
    let animId: number
    const canvas = canvasRef.current
    const video = videoRef.current

    function tick() {
      if (video && canvas && video.readyState === video.HAVE_ENOUGH_DATA) {
        const ctx = canvas.getContext('2d')
        if (ctx) {
          canvas.height = video.videoHeight
          canvas.width = video.videoWidth
          ctx.drawImage(video, 0, 0, canvas.width, canvas.height)
          const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height)
          const code = jsQR(imageData.data, imageData.width, imageData.height, {
            inversionAttempts: 'dontInvert',
          })
          if (code && code.data) {
            onScan(code.data)
            return // Stop ticking on success
          }
        }
      }
      animId = requestAnimationFrame(tick)
    }

    animId = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(animId)
  }, [onScan])

  if (typeof document === 'undefined') return null

  return createPortal(
    <div className="scansync-overlay">
      <div className="scansync-modal">
        <div className="scansync-header">
          <h3>{title ?? t('profile.scan')}</h3>
          <button className="scansync-close-btn" onClick={onClose} aria-label={t('profile.scan.cancel')}>
            ✕
          </button>
        </div>

        <div className="scansync-body">
          {error ? (
            <p className="scansync-error">{error}</p>
          ) : (
            <div className="scansync-video-container">
              <video ref={videoRef} className="scansync-video" />
              <canvas ref={canvasRef} style={{ display: 'none' }} />
              <div className="scansync-laser" />
              <div className="scansync-corner scansync-corner--tl" />
              <div className="scansync-corner scansync-corner--tr" />
              <div className="scansync-corner scansync-corner--bl" />
              <div className="scansync-corner scansync-corner--br" />
            </div>
          )}
          <p className="scansync-hint">
            {hint ?? t('auth.scan2sync.desc')}
          </p>
        </div>
      </div>
    </div>,
    document.body,
  )
}
