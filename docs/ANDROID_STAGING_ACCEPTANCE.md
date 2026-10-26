# Isolated Android staging acceptance

This prepares an APK for the real staging service. A successful compile or APK
verification does not establish Google sign-in, Drive sync, or device acceptance.
Keep the installed Atomic Test app and its data intact throughout this process.

## Package and configuration

`ATOMIC_ANDROID_STAGING=true` opts Android Gradle builds into the fixed package
`com.notes.atomic.staging` with launcher label **Atomic Staging**. Any other value,
including an unset variable, retains `com.notes.atomic`: release is **Atomic**,
and debug/profile remain **Atomic Test**. The namespace and launcher class remain
`com.notes.atomic` and `com.notes.atomic.MainActivity`. No product flavors or
runtime feature flags are added.

The **Staging Android** workflow compiles the real `lib/main.dart`. Pull requests
compile default and staging debug/release configurations and inspect the resulting
APK identities with `aapt`. The PR job uses a synthetic public client ID only to
compile, consumes no signing secrets, and publishes no installable artifact.

The manual release job runs only on `main` in a non-fork repository, checking out
the exact dispatched source SHA. Dispatch only after that main commit has passed
review and required CI. The release endpoint is fixed in the workflow:

```text
https://atomic-notes-app-server-staging.vercel.app/api
```

Supply `google_server_client_id` as the **public Web OAuth client ID** matching
the deployed staging server's `GOOGLE_CLIENT_ID`. Both must belong to the separate
staging Google project. The Android OAuth client ID is a different credential;
its format alone cannot distinguish it from a Web client ID. Verify the type and
project in Google Auth platform before dispatch. Never supply a client secret.

## Dedicated signer handoff

Create and retain a dedicated staging keystore privately. Reuse that same signer
for subsequent staging updates; losing it requires a separate recovery decision.
Add only these repository Actions secrets through the owner's private secret
handoff, without copying production signing credentials:

| Secret | Private value |
| --- | --- |
| `STAGING_ANDROID_KEYSTORE_BASE64` | Single-line base64 of the staging keystore |
| `STAGING_ANDROID_KEYSTORE_PASSWORD` | Staging keystore password |
| `STAGING_ANDROID_KEY_ALIAS` | Alias within that keystore |
| `STAGING_ANDROID_KEY_PASSWORD` | Private-key password |

The manual job fails when any value is missing and rejects an Android Debug
certificate. It restores the key and escaped `android/key.properties` only on the
runner, removes them in an `always()` cleanup step, and uploads only the verified
APK and public provenance. Do not upload the keystore, credential JSON, build
directories, or properties file. No production signing secrets are referenced.

## Build, inspect, and register

1. Confirm the separate staging Google project has Drive API enabled, an External
   consent app in Testing, the spare account in Test users, and the staging Web
   client configured on the server. Confirm the server callback is exactly
   `https://atomic-notes-app-server-staging.vercel.app/api/auth/callback`.
2. Dispatch **Staging Android** on the reviewed `main` commit using that Web
   client ID. The build uses pubspec's version name and the workflow `run_number`
   as its staging version code. Reruns retain the same code; a later dispatch
   increments it. Keep this workflow's run sequence when updating this package.
3. Download the exact successful run's `atomic-staging-arm64-<run>-<attempt>`
   artifact. It contains `atomic-staging-arm64.apk` and `provenance.json`. The
   workflow verifies package, label, launcher, arm64 ABI, version, signature,
   source SHA, public endpoint/client ID presence, and absence of signing files,
   recognizable Google client-secret and private-key material. This bounded scan
   is not a general proof that every possible secret format is absent.
4. Independently verify the downloaded APK with Android SDK tools:

   ```sh
   apksigner verify --verbose --print-certs atomic-staging-arm64.apk
   aapt dump badging atomic-staging-arm64.apk
   sha256sum atomic-staging-arm64.apk
   ```

   Match SHA-256 digest, SHA-1/SHA-256 signer fingerprints, package
   `com.notes.atomic.staging`, label **Atomic Staging**, launcher
   `com.notes.atomic.MainActivity`, version, accepted source commit, workflow and
   exact run/attempt against provenance. Compare the signer fingerprints with
   the privately retained staging key's public certificate. Reject an unexpected
   package, source, endpoint, signer, synthetic client ID, or missing provenance.
5. In the **same separate staging Google project** as the server's Web OAuth
   client, create an **Android** OAuth client for package
   **`com.notes.atomic.staging`** and the **exact SHA-1 from the verified staging
   APK certificate**. Do not use the installed Atomic Test app's signer, the
   normal `com.notes.atomic` package, or the APK file's SHA-256 digest. Record the
   Android client registration and Web client/project match without secrets.

## Device/provider acceptance remains a separate gate

Before installation, take and verify a fresh private preservation snapshot and
confirm Atomic Test remains installed. Install the verified separate staging APK
without uninstalling, clearing, or rebinding Atomic Test. The owner selects the
spare Google account and approves the requested consent; never use an account
containing existing Atomic Notes data for this round.

Record first and returning login, disposable text/checklist/image note creation,
Drive sync and readback, logout and reopen through the real staging endpoint.
Check account separation and retain the existing app/data. External Google apps
in Testing that request Drive access can require sign-in again after seven days.
No automated compile or artifact check completes this real-account acceptance.

Official Android configuration references:
[application ID suffixes](https://developer.android.com/build/build-variants),
[manifest placeholders](https://developer.android.com/build/manage-manifests).
Google setup references:
[OAuth clients](https://developers.google.com/workspace/guides/create-credentials),
[consent and test users](https://developers.google.com/workspace/guides/configure-oauth-consent),
[testing token lifetime](https://developers.google.com/identity/protocols/oauth2/web-server#expiration).
