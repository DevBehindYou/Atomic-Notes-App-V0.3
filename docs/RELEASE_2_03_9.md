# Release target: 2.03.9

Owner-selected version, 1 October 2026. Metadata is `2.03.9+9`: version name 2.03.9 and base build number 9. AppInfoText stays aligned with pubspec so the displayed version and notification audience version match. Historical compatibility tests using 2.03.5 remain unchanged.

The published 2.03.5 release describes base build 8 and split-APK version codes 1008 (armeabi-v7a), 2008 (arm64-v8a), and 4008 (x86_64). Flutter 3.44.8 uses `ABI_VERSION * 1000 + versionCode` for split APKs, so base 9 is expected to produce 1009, 2009 and 4009 respectively. These expectations must be checked against the actual signed APK metadata before release. A universal/debug APK's base code 9 is not interchangeable with a previously installed split APK's higher code; distribution must use the verified appropriate release artifact.

The application ID remains `com.notes.atomic`. Publication requires the original release signing identity, a tested in-place upgrade from the existing signed 2.03.5 artifact, configured new API URL, compatible Server rollout, and completion of release gates. Do not uninstall or clear user storage to work around an update failure. The signed build workflow remains manual and is not triggered by this metadata change.

This version PR is based on main independently of the still-open accessibility PR #19. Include all intended reviewed fixes in the final release commit before building. Passing verification CI produces a non-production debug APK only; it does not publish, sign the final release, change the API address, activate expiry or deploy infrastructure.
