// 取当前 GPS 坐标（用于 SOS 让 Group/Community 直接看到位置）。
// 失败/拒绝/不支持都返回 null，SOS 仍照常发出，不阻塞求助。

export function getCurrentCoords(
  timeoutMs = 8000,
): Promise<{ lat: number; lng: number } | null> {
  return new Promise((resolve) => {
    if (!('geolocation' in navigator)) return resolve(null)
    navigator.geolocation.getCurrentPosition(
      (p) => resolve({ lat: p.coords.latitude, lng: p.coords.longitude }),
      () => resolve(null),
      { enableHighAccuracy: true, timeout: timeoutMs, maximumAge: 60_000 },
    )
  })
}
