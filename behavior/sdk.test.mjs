import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createBehaviorSession } from './sdk.mjs';

test('a CLI that stops answering fails the session instead of hanging the run', async () => {
  const silentCLI = join(mkdtempSync(join(tmpdir(), 'reflex-sdk-')), 'silent-cli');
  writeFileSync(silentCLI, '#!/bin/sh\nexec sleep 30\n');
  chmodSync(silentCLI, 0o755);
  const session = createBehaviorSession({ cli: silentCLI, answerTimeoutMs: 300 });
  await assert.rejects(session.ls(), /did not answer \{"cmd":"ls"\} within 300 ms/);
});
