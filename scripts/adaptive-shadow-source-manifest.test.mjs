import test from 'node:test'
import assert from 'node:assert/strict'
import { verifyAdaptiveShadowSource } from './adaptive-shadow-source-manifest.mjs'

test('accepts only the audited adaptive source set', async () => {
  const result = await verifyAdaptiveShadowSource(process.cwd())
  assert.deepEqual(result.unexpected, [])
  assert.equal(result.groupFixPresent, true)
  assert.equal(result.excludedAclPresent, false)
  assert.equal(result.protectedLiveDrift.length, 0)
})
