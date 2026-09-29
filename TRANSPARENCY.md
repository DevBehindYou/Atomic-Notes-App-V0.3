# Transparency

Atomic Notes exists because a data breach taught its developer a hard lesson: most apps won't tell you plainly what happens to your data. This page does. It describes how Atomic Notes 2.03.5 handles your notes, what is protected, what isn't, and how to check it yourself. If any of this ever stops being accurate, treat it as a bug and report it.

## What we collect

Almost nothing. Atomic Notes ships no analytics, no crash reporter, no advertising SDK and no third-party trackers. It doesn't build a profile of you or measure how you use the app.

To run your account, the Atomic Notes server keeps:

- your Google account id, email address and display name, from Google sign-in, and the username you pick
- your energy and coin balances and a ledger of how they changed
- metadata for each note: its id, whether it's a note or a checklist, the pinned and deleted flags, timestamps, and the id of its file in your Google Drive
- an encrypted Google token, so the server can write your note files to your Drive
- a short log of account and security events, such as sign-ins
- which team announcements you have read or dismissed

It doesn't keep your note titles, note text or checklist items. Those live on your phone and in your own Drive.

## Where your notes live

On your phone first. Atomic Notes is local-first: every note is saved to on-device storage as you type, and the app works the same with or without a connection.

When you sync, each note is saved as its own `.atomic` file in a `My-Atomic-Notes` folder in your Google Drive. The app asks Google for the `drive.file` scope, which lets it see only the files it created. You can turn cloud sync off, and your notes then stay on the phone only.

## What is protected

- Traffic between the app and the server uses HTTPS.
- In the cloud, your notes sit in your own Google Drive, under your Google account's security.
- **The vault (optional).** Turn it on and the app gives you a 6-word recovery phrase. Argon2id derives a key from it on your phone, and AES-256-GCM seals every note before it leaves the device. Your Drive and the server then hold only ciphertext. The phrase and the key never leave your phone.
- On the device: an optional biometric lock, optional two-step verification with an authenticator app, blocked screenshots and screen recording, and Android secure storage for the session and the vault key.

## What isn't protected

We would rather be exact than impressive.

- **With the vault off**, your notes are plain text in your Google Drive, and they pass through the Atomic Notes server as plain text on the way there. The server doesn't store them, but it handles them in transit. Turn the vault on if that matters to you.
- The app doesn't add its own encryption to the notes stored on your phone. It relies on Android's device encryption.
- If you lose your recovery phrase, no one can decrypt your vault notes on a new device. Not the developer, not Google. Write the phrase down.

## No AI, no ads, no data sale

Atomic Notes has no AI features. Your notes are never sent to a model and never used as training data. There are no ads in the app.

Cloud sync runs on Atomic Energy, which refills for free every day. Atomic Coins add more energy or more note capacity. Coins buy speed and room, never access to your notes. The project will never sell your data, and it's built so that there's nothing to sell.

## Source available

The full app source is public in this repository, so anyone can read what the app does instead of taking this page on faith. The code is proprietary, not open source: the [license](LICENSE) lets you read it, build it to check it against the official release, and report security issues, but not copy or reuse it.

## How to hold us to this

Verify, don't trust:

- [`pubspec.yaml`](pubspec.yaml) lists every library the app ships. There's no analytics, crash-reporting or ad SDK in it.
- [`lib/security/vault.dart`](lib/security/vault.dart) and [`lib/security/vault_crypto.dart`](lib/security/vault_crypto.dart) hold the vault's key derivation and encryption.
- Every release on [GitHub Releases](https://github.com/DevBehindYou/Atomic-Notes-App-V0.2/releases) lists the SHA-256 of each APK and the GitHub Actions run that built it.

If you find anything that contradicts this page, that's a defect we want to fix. Reach the developer through the links in the [README](README.md).

---

*Last reviewed: 2026-09-28, for version 2.03.5.*
