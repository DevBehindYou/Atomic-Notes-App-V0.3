# W1: guarded browser compile feasibility

This target is a development gate, not an Atomic Notes WebApp beta. Android
continues through its existing startup. Browser `main()` returns after showing
`BrowserPreviewGate`, before App auth, secure storage, Hive, vault initialization,
repositories, routes or cloud activity. There is no enable flag or fallback that
pretends native authentication/key storage is working in a browser.

The network-error classifier uses a conditional `dart:io` import. Native socket,
TLS and HTTP failures retain their classification; portable HTTP
`ClientException` keeps the existing 5/15/45-second retry policy. Arbitrary error
text, timeouts and Server refusals do not become connectivity failures.

The web scaffold loads Flutter's local modern `flutter_bootstrap.js`. It does not
register a worker or link an install manifest. Legacy favicon/manifest/icon
scaffold files remain unreferenced pending the platform branding and PWA gates.
No external fonts or scripts are added. CI disables the generated caching worker
for pinned Flutter 3.44.8 and keeps renderer resources local to the build.

## Evidence and its limits

The separate `Guarded WebApp compile feasibility` CI job resolves the committed
lockfile using Flutter 3.44.8, compiles actual `lib/main.dart` in release mode,
and tests actual browser entry in headless Chrome. It publishes only bounded
`ci-web-compile-proof.json`: source identity, SDK version, compiler/test exit
codes, three allowlisted public test outcomes and hashes/sizes of three known
build files. Bundles, credentials, compiler output and raw test events are not
uploaded by this job. Python parser tests reject skipped/missing test evidence.

**Passing proves:** this guarded main can compile under the pinned dependency
graph, the browser gate opens without the checked Hive boxes or native routes,
and tested portable network classification is preserved. Existing native
analyzer/tests/debug APK remain required alongside it.

**Passing does not prove:** the tree-shaken native App routes work in browsers,
an IndexedDB store is durable, Google authentication/session cookies are safe,
vault crypto/key policy is interoperable, cloud sync is correct, a PWA is
installable, or the compiled release bundle has passed a browser runtime test.
The browser widget test is a test harness, not a deployed release smoke test.
There is no deploy/publish step in W1.

## Dependencies before browser editing or cloud access

1. W2: audited IndexedDB storage adapter, one writer tab, owner/context fencing,
   durable pending requests, reload/crash/quota handling and user export.
2. W3: browser session gateway, server-managed OAuth, cookie/CSRF/context checks,
   verified identity mapping and read-only integration. No native bearer/key
   adapter may be silently reused as a browser equivalent.
3. W4: cross-platform conflict/replay/economy/E2E compatibility, browser KDF/key
   handling and multi-tab safe logout proven in disposable integrations.
4. W5: verified rescue protocol, supported browser matrix, responsive navigation,
   platform icons, worker update/rollback safety, final origin and beta release.

The detailed authority is the workspace's WebApp source audit and implementation
plan dated 2026-10-12. New separate Server deployments remain an architectural
proposal until shared-writer and legacy compatibility boundaries are reviewed.
