// CI-only pure functions from the actual locked Server; no routes or storage.
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { remoteNoteRowSchema } from '../server-fixture/src/types/noteWire.ts';
import { fingerprintOf } from '../server-fixture/src/lib/syncFingerprint.ts';

const fixture = readFileSync(new URL('../test/fixtures/sync_envelope_vectors.dart', import.meta.url), 'utf8');
const vectors = JSON.parse(fixture.split("r'''", 2)[1].split("'''", 1)[0]);
const digest = value => createHash('sha256').update(value).digest('hex');
const outcomes = {};
if (process.argv.includes('--emitted-wire')) {
  const emitted = JSON.parse(readFileSync(0, 'utf8'));
  if (!Array.isArray(emitted) || emitted.length !== vectors.length) throw new Error('public wire set');
  const seen = new Set();
  for (const receipt of emitted) {
    const vector = vectors.find(value => value.case === receipt.case);
    if (!vector || seen.has(receipt.case) || typeof receipt.wire !== 'string') throw new Error('public wire identity');
    seen.add(receipt.case);
    const wire = JSON.parse(receipt.wire);
    const rows = wire.rows.map(row => remoteNoteRowSchema.parse(row));
    const projected = JSON.stringify({ rows, requestId: vector.requestId, mode: vector.mode,
      ...(vector.attemptId ? { logoutAttemptId: vector.attemptId } : {}) });
    outcomes[vector.case] = projected === receipt.wire &&
      fingerprintOf(rows, vector.mode) === vector.expected.fingerprint &&
      Buffer.byteLength(receipt.wire) === vector.expected.wireBytes &&
      digest(receipt.wire) === vector.expected.wireSha256 &&
      digest(JSON.stringify(rows)) === vector.expected.projectedSha256;
  }
  process.stdout.write(JSON.stringify({ version: 1, outcomes }) + '\n');
  process.exit(Object.values(outcomes).every(value => value === true) ? 0 : 1);
}
for (const vector of vectors) {
  const rows = vector.rows.map(row => remoteNoteRowSchema.parse(row));
  const wire = JSON.stringify({ rows, requestId: vector.requestId, mode: vector.mode,
    ...(vector.attemptId ? { logoutAttemptId: vector.attemptId } : {}) });
  const expected = vector.expected;
  outcomes[vector.case] = fingerprintOf(rows, vector.mode) === expected.fingerprint &&
    Buffer.byteLength(wire) === expected.wireBytes && digest(wire) === expected.wireSha256 &&
    digest(JSON.stringify(rows)) === expected.projectedSha256;
}
const row = vectors[0].rows[0];
const invalidVersions = [null, -1, 1.5, '1'];
const invalidEnc = [null, -1, 2, 0.5, '0'];
outcomes['N1 actual Server numeric and mixed checklist controls'] =
  invalidVersions.every(base_version => !remoteNoteRowSchema.safeParse({ ...row, base_version }).success) &&
  invalidEnc.every(enc_v => !remoteNoteRowSchema.safeParse({ ...row, enc_v }).success) &&
  !remoteNoteRowSchema.safeParse({ ...row, items: [{ text: 'mixed task', d: true }] }).success &&
  remoteNoteRowSchema.parse({ ...row, base_version: Number.MAX_SAFE_INTEGER }).base_version === Number.MAX_SAFE_INTEGER;
// Fixed names and booleans only. No projected rows or raw diagnostics leave CI.
process.stdout.write(JSON.stringify({ version: 1, outcomes }) + '\n');
if (!Object.values(outcomes).every(value => value === true)) process.exitCode = 1;
