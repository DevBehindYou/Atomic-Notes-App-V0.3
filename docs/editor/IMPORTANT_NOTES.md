# Important notes

The editor's **Mark important** control sits beside Pin. It changes only the
draft until Done or Save. Discard retains the original note. Important cards
have a black surface, white title, light content and a labelled importance
icon; pinning, ordering and mixed text/checklist editing remain independent.

The fixed card palette uses `#000000` background, `#FFFFFF` title, `#F0F1EB`
content and `#A4A6AF` outline. The white title has 21:1 contrast against
black. Tests require 4.5:1 text and 3:1 outline contrast.

Importance survives local Hive maps, copies, ordinary and logout conflict
copies, encrypted storage and remote reconstruction. Local false is represented
by omission, preserving the legacy map shape and content signature. New remote
writes explicitly send false so that users can clear a previous true value.
The optional sync-envelope field follows `pinned`; legacy envelopes which omit
it retain their canonical bytes, including pending replay fingerprints.

Requires Server support from merged Server PR79 (`ba4bc3b13b3d3a529ef7f1bcacc1edc5a0b3f618`)
before App release. CI pins this accepted Server for the disposable wire proof.
An old client omitting the field preserves stored importance on that Server.
Rolling the Server back while new clients are active would strip this field and
can break their envelope fingerprints; coordinate any rollback before release.

Verification: `test/note_importance_test.dart` covers legacy signatures, explicit
clearing, wire projection, invalid flags, contrast, save/discard and card style.
`test/mixed_note_persistence_test.dart` covers Hive and actual repository sealing
with plaintext and AES content. Physical-device and production staging acceptance
remain separate gates; these tests do not establish either.
