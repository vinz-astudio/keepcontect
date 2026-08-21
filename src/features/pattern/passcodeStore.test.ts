import { beforeEach, describe, expect, it, vi } from 'vitest'
import {
  PASSCODE_MAX_LENGTH,
  PASSCODE_MIN_LENGTH,
  availableUnlockMethods,
  getPasscodeHash,
  getPatternHash,
  isPasscodeAcceptable,
  purgeLocalSafetyState,
  setPasscode,
  setPattern,
  verifyPasscode,
  verifyPattern,
} from './patternStore'

const storeMap = new Map<string, string>()
vi.stubGlobal('localStorage', {
  getItem: (k: string) => storeMap.get(k) ?? null,
  setItem: (k: string, v: string) => storeMap.set(k, v),
  removeItem: (k: string) => storeMap.delete(k),
  clear: () => storeMap.clear(),
  get length() {
    return storeMap.size
  },
  key: (i: number) => [...storeMap.keys()][i] ?? null,
})

const uid = 'user-1'

beforeEach(() => storeMap.clear())

describe('passcode and pattern are independent credentials', () => {
  // 用户可以只设一个,也可以两个都设,解锁时自己挑。设了密码不该让手势失效。
  it('leaves the pattern working after a passcode is set', async () => {
    await setPattern(uid, [1, 2, 3, 4])
    await setPasscode(uid, '4821')
    expect(await verifyPattern(uid, [1, 2, 3, 4])).toBe(true)
    expect(await verifyPasscode(uid, '4821')).toBe(true)
  })

  it('keeps them in separate slots', async () => {
    await setPattern(uid, [1, 2, 3, 4])
    await setPasscode(uid, '4821')
    expect(getPatternHash(uid)).not.toBe(getPasscodeHash(uid))
  })

  // 密码「1234」和手势 1-2-3-4 不能算出同一个哈希,否则两个本该独立的凭据在
  // 存储层变成同一个值。
  it('keeps passcodes and patterns in separate hash domains', async () => {
    await setPattern(uid, [1, 2, 3, 4])
    await setPasscode(uid, '1234')
    expect(getPasscodeHash(uid)).not.toBe(getPatternHash(uid))
  })

  it('verifies the passcode it stored', async () => {
    await setPasscode(uid, '90210')
    expect(await verifyPasscode(uid, '90210')).toBe(true)
    expect(await verifyPasscode(uid, '90211')).toBe(false)
  })

  it('reports which ways this account can be unlocked', async () => {
    expect(availableUnlockMethods(uid)).toEqual({ pattern: false, passcode: false })
    await setPasscode(uid, '4821')
    expect(availableUnlockMethods(uid)).toEqual({ pattern: false, passcode: true })
    await setPattern(uid, [0, 1, 2])
    expect(availableUnlockMethods(uid)).toEqual({ pattern: true, passcode: true })
  })

  it('rejects anything that is not digits of a workable length', () => {
    expect(isPasscodeAcceptable('123')).toBe(false)
    expect(isPasscodeAcceptable('1'.repeat(PASSCODE_MAX_LENGTH + 1))).toBe(false)
    expect(isPasscodeAcceptable('12a4')).toBe(false)
    expect(isPasscodeAcceptable('1'.repeat(PASSCODE_MIN_LENGTH))).toBe(true)
  })

  it('takes both credentials with it when the device is purged on sign-out', async () => {
    await setPattern(uid, [1, 2, 3])
    await setPasscode(uid, '4821')
    purgeLocalSafetyState()
    expect(getPatternHash(uid)).toBeNull()
    expect(getPasscodeHash(uid)).toBeNull()
  })
})
