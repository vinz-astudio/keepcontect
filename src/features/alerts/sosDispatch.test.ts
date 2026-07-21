import { describe, expect, it, vi } from 'vitest'
import { dispatchSos } from './sosDispatch'

describe('dispatchSos with dependencies injection', () => {
  // Test 1: Zero-arg raiseSos is called exactly once and returns its result
  it('calls raiseSos exactly once with zero arguments and returns the alert id', async () => {
    const raiseSos = vi.fn().mockResolvedValue('alert-123')
    const triggerPushDispatch = vi.fn().mockResolvedValue(undefined)
    const getCurrentCoords = vi.fn().mockResolvedValue({ lat: 1.2, lng: 3.4 })
    const updateSosLocation = vi.fn().mockResolvedValue(true)

    const result = await dispatchSos({
      raiseSos,
      triggerPushDispatch,
      getCurrentCoords,
      updateSosLocation,
    })

    expect(result).toBe('alert-123')
    expect(raiseSos).toHaveBeenCalledTimes(1)
    expect(raiseSos).toHaveBeenCalledWith()
  })

  // Test 2: Raise failure short-circuits execution (error propagates)
  it('propagates raiseSos failure and short-circuits execution', async () => {
    const raiseSos = vi.fn().mockRejectedValue(new Error('DB Error'))
    const triggerPushDispatch = vi.fn()
    const getCurrentCoords = vi.fn()
    const updateSosLocation = vi.fn()

    await expect(
      dispatchSos({
        raiseSos,
        triggerPushDispatch,
        getCurrentCoords,
        updateSosLocation,
      })
    ).rejects.toThrow('DB Error')

    // Wait short time to ensure detached calls didn't run
    await new Promise((r) => setTimeout(r, 20))

    expect(triggerPushDispatch).not.toHaveBeenCalled()
    expect(getCurrentCoords).not.toHaveBeenCalled()
    expect(updateSosLocation).not.toHaveBeenCalled()
  })

  // Test 3: Assert immediate invocation but non-awaiting settlement
  it('invokes push and geo immediately but does not await their settlement', async () => {
    const raiseSos = vi.fn().mockResolvedValue('alert-123')
    
    let pushSettled = false
    const triggerPushDispatch = vi.fn().mockImplementation(() => {
      return new Promise<void>((resolve) => {
        setTimeout(() => {
          pushSettled = true
          resolve()
        }, 50)
      })
    })

    let geoSettled = false
    const getCurrentCoords = vi.fn().mockImplementation(() => {
      return new Promise<{ lat: number; lng: number } | null>((resolve) => {
        setTimeout(() => {
          geoSettled = true
          resolve({ lat: 1.2, lng: 3.4 })
        }, 50)
      })
    })

    const updateSosLocation = vi.fn().mockResolvedValue(true)

    const result = await dispatchSos({
      raiseSos,
      triggerPushDispatch,
      getCurrentCoords,
      updateSosLocation,
    })

    // 1. Immediately after dispatchSos returns, both mocks must have been called
    expect(result).toBe('alert-123')
    expect(triggerPushDispatch).toHaveBeenCalledTimes(1)
    expect(getCurrentCoords).toHaveBeenCalledTimes(1)

    // 2. But their returned promises must NOT have settled yet (proving no awaiting)
    expect(pushSettled).toBe(false)
    expect(geoSettled).toBe(false)
    expect(updateSosLocation).not.toHaveBeenCalled()

    // 3. Wait for settlement and verify
    await new Promise((r) => setTimeout(r, 60))
    expect(pushSettled).toBe(true)
    expect(geoSettled).toBe(true)
    expect(updateSosLocation).toHaveBeenCalledTimes(1)
  })

  // Test 4: Push synchronous throw is swallowed
  it('swallows push synchronous throw and does not crash or reject the call', async () => {
    const raiseSos = vi.fn().mockResolvedValue('alert-123')
    const triggerPushDispatch = vi.fn().mockImplementation(() => {
      throw new Error('Push sync crash')
    })
    const getCurrentCoords = vi.fn().mockResolvedValue(null)

    const result = await dispatchSos({
      raiseSos,
      triggerPushDispatch,
      getCurrentCoords,
    })

    expect(result).toBe('alert-123')
    expect(triggerPushDispatch).toHaveBeenCalledTimes(1)
  })

  // Test 5: Push asynchronous rejection is swallowed
  it('swallows push asynchronous rejection and does not crash or reject the call', async () => {
    const raiseSos = vi.fn().mockResolvedValue('alert-123')
    const triggerPushDispatch = vi.fn().mockRejectedValue(new Error('Push async rejection'))
    const getCurrentCoords = vi.fn().mockResolvedValue(null)

    const result = await dispatchSos({
      raiseSos,
      triggerPushDispatch,
      getCurrentCoords,
    })

    expect(result).toBe('alert-123')
    
    // Wait for the async tasks to finish
    await new Promise((r) => setTimeout(r, 10))
    expect(triggerPushDispatch).toHaveBeenCalledTimes(1)
  })

  // Test 6: Never-settling geo promise does not block the return of dispatchSos
  it('does not delay return of dispatchSos even if geolocation hangs/never settles', async () => {
    const raiseSos = vi.fn().mockResolvedValue('alert-123')
    const getCurrentCoords = vi.fn().mockReturnValue(new Promise(() => {}))
    const updateSosLocation = vi.fn()

    const startTime = Date.now()
    const result = await dispatchSos({
      raiseSos,
      getCurrentCoords,
      updateSosLocation,
    })
    const duration = Date.now() - startTime

    expect(result).toBe('alert-123')
    expect(duration).toBeLessThan(100) // completed immediately

    // Both push and geo were called immediately
    expect(getCurrentCoords).toHaveBeenCalledTimes(1)
    expect(updateSosLocation).not.toHaveBeenCalled()
  })

  // Test 7: Geo resolving null does not call updateSosLocation
  it('does not call updateSosLocation if geo resolves to null', async () => {
    const raiseSos = vi.fn().mockResolvedValue('alert-123')
    const getCurrentCoords = vi.fn().mockResolvedValue(null)
    const updateSosLocation = vi.fn()

    await dispatchSos({
      raiseSos,
      getCurrentCoords,
      updateSosLocation,
    })

    await new Promise((r) => setTimeout(r, 10))
    expect(getCurrentCoords).toHaveBeenCalledTimes(1)
    expect(updateSosLocation).not.toHaveBeenCalled()
  })

  // Test 8: Geo resolving coordinates calls updateSosLocation exactly once
  it('calls updateSosLocation exactly once with resolved coordinates', async () => {
    const raiseSos = vi.fn().mockResolvedValue('alert-123')
    const getCurrentCoords = vi.fn().mockResolvedValue({ lat: 40.7128, lng: -74.0060 })
    const updateSosLocation = vi.fn().mockResolvedValue(true)

    await dispatchSos({
      raiseSos,
      getCurrentCoords,
      updateSosLocation,
    })

    await new Promise((r) => setTimeout(r, 10))
    expect(getCurrentCoords).toHaveBeenCalledTimes(1)
    expect(updateSosLocation).toHaveBeenCalledTimes(1)
    expect(updateSosLocation).toHaveBeenCalledWith(40.7128, -74.0060)
  })

  // Test 9: updateSosLocation rejection is swallowed and does not retry
  it('swallows updateSosLocation rejection, does not retry, and does not crash the call', async () => {
    const raiseSos = vi.fn().mockResolvedValue('alert-123')
    const getCurrentCoords = vi.fn().mockResolvedValue({ lat: 40.7128, lng: -74.0060 })
    const updateSosLocation = vi.fn().mockRejectedValue(new Error('Update failed'))

    const result = await dispatchSos({
      raiseSos,
      getCurrentCoords,
      updateSosLocation,
    })

    expect(result).toBe('alert-123')

    await new Promise((r) => setTimeout(r, 10))
    expect(getCurrentCoords).toHaveBeenCalledTimes(1)
    expect(updateSosLocation).toHaveBeenCalledTimes(1) // Called once, no retry
  })

  // Test 10: updateSosLocation returning false causes no retry
  it('causes no retry and does not crash if updateSosLocation resolves to false', async () => {
    const raiseSos = vi.fn().mockResolvedValue('alert-123')
    const getCurrentCoords = vi.fn().mockResolvedValue({ lat: 40.7128, lng: -74.0060 })
    const updateSosLocation = vi.fn().mockResolvedValue(false)

    const result = await dispatchSos({
      raiseSos,
      getCurrentCoords,
      updateSosLocation,
    })

    expect(result).toBe('alert-123')

    await new Promise((r) => setTimeout(r, 10))
    expect(getCurrentCoords).toHaveBeenCalledTimes(1)
    expect(updateSosLocation).toHaveBeenCalledTimes(1) // Called once, no retry
  })

  // Test 11: Geo synchronous throw is swallowed
  it('swallows geo synchronous throw and does not crash or reject the call', async () => {
    const raiseSos = vi.fn().mockResolvedValue('alert-123')
    const getCurrentCoords = vi.fn().mockImplementation(() => {
      throw new Error('Geo sync crash')
    })
    const updateSosLocation = vi.fn()

    const result = await dispatchSos({
      raiseSos,
      getCurrentCoords,
      updateSosLocation,
    })

    expect(result).toBe('alert-123')
    expect(getCurrentCoords).toHaveBeenCalledTimes(1)
    expect(updateSosLocation).not.toHaveBeenCalled()
  })
})
