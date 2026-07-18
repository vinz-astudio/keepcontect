import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, test } from 'vitest';

const currentDir = path.dirname(fileURLToPath(import.meta.url));
const manifestPath = path.resolve(currentDir, '../../android/app/src/main/AndroidManifest.xml');
const manifest = readFileSync(manifestPath, 'utf-8');

function receiverBlock(name: string): string {
  const re = new RegExp(`<receiver\\b[^>]*android:name="\\.${name}"[\\s\\S]*?</receiver>`, 'm');
  const match = manifest.match(re);
  if (!match) throw new Error(`receiver .${name} not found in manifest`);
  return match[0];
}

describe('AndroidManifest.xml — ActivityTransitionReceiver exposure', () => {
  test('is not exported', () => {
    expect(receiverBlock('ActivityTransitionReceiver')).toMatch(/android:exported\s*=\s*"false"/);
  });

  test('declares no intent-filter (GMS delivery is via explicit PendingIntent only)', () => {
    expect(receiverBlock('ActivityTransitionReceiver')).not.toMatch(/<intent-filter>/);
  });

  test('PassivePingReceiver stays non-exported (regression guard, no collateral change)', () => {
    expect(receiverBlock('PassivePingReceiver')).toMatch(/android:exported\s*=\s*"false"/);
  });
});
