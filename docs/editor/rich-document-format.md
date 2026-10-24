# Rich document storage v2

The outer Note, Hive map, cloud envelope, encryption version, and Drive `.atomic`
file format remain unchanged. A rich note uses `kind: text`, a JSON `body`, and
exactly one unchecked item with text `atomic-notes:rich-document:v2`.

```json
{"v":2,"tags":["Release"],"blocks":[{"text":"Ship","checklist":true,"done":false,"styles":[[0,4,1]]}]}
```

Blocks always contain `text`, `checklist`, `done`, and `styles`. An image block
also contains `image`: canonical bare base64 JPEG bytes. Image blocks have empty
text/styles and false checklist/done values. Images never contain remote URLs,
device paths, or separate cloud references.

Each style is `[start,end,flags]` with UTF-16 offsets, exclusive end, and bits:
bold 1, italic 2, underline 4, strike 8, heading 16. Flags may combine. Ranges must
be nonempty and within the block text. Tags trim surrounding whitespace,
deduplicate without case, retain display case/order, and allow up to 12 tags of
40 characters each. Tags and images are content and are sealed with body/items
when the vault is unlocked.

Opening old plain text, todos, or task-lines v1 never infers formatting from
their content. No-op saves preserve their original representations and content
signatures. Rich encoding starts only on an actual tag/style/image change;
already-rich notes retain their version on later checklist/prose changes.
Cleanup removes blank prose/tasks while retaining images and tag-only notes.
Clearing all content and tags removes the envelope.

An unknown reserved rich version, invalid JSON, unsupported properties, invalid
style/image, or oversized body projects to `Unsupported note format` and is
read-only. The original body/items remain intact; every document mutator refuses
and `toNote` returns an unchanged copy. Repository saves reject such content.

`NoteContentBudget` checks title 300 UTF-16 units, body 262144 units, encrypted
payload 393216 characters, and full parsed row 400000 UTF-8 JSON bytes, including
the Server's additional `encV` refinement field. It checks both plaintext and
future encrypted representations. Ciphertext length is
`4 * ceil((UTF8(JSON({title,body,items})).length + 28) / 3)` for nonce/MAC overhead.

New image additions are limited to three per note, each at most 60,000 raw JPEG
bytes, with a 180,000-byte aggregate budget. The legacy per-image decoder still
accepts up to 60 KiB, preserving old saved bytes. Header validation requires JPEG start/end
markers, a supported frame header, dimensions at most 4096 on either axis, and at
most 4194304 pixels. Header validation does not replace the platform image
decoder: imports are decoded/re-encoded before insertion, and rendering handles
decode failures safely. No async attachment upload, orphan cleanup, or media
cache is involved. Speech recognition inserts ordinary text; audio is not stored.

Deploy the matching larger Server note bounds before releasing the 60 KB client.
The request/batch limits and ten-note pull pagination remain unchanged. See
[the 60 KB implementation](IMAGES_60KB_2026-10-24.md) for rollout and verification.

This format preserves old notes, but older released applications cannot render
or safely edit rich v2 content. No new Server minimum-client gate is introduced
by this local format. Use a current app on every editing device; a future
minimum-client/format-capability protocol is needed for enforced mixed-version
write protection, especially for opaque encrypted notes.
