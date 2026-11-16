# GitHub workflows

## Flutter verification

Push `.github/workflows/flutter-ci.yml` in this repository, then open
**Actions → Flutter verification → Run workflow** (pushes to main and pull
requests also run it). No local Flutter SDK or Pages configuration is needed.

The hosted workflow resolves packages, treats all analyzer findings as fatal,
and runs the existing tests. It builds a debug APK only when Android packaging
is enabled (see below). That APK uses placeholder API/OAuth configuration and
is not a production release; when packaging is enabled its upload remains
required. Diagnostic upload failure is reported without masking build errors.
Artifacts expire after one day. If quota is full, clear obsolete artifacts
in GitHub before rerunning. No workflow deletes existing artifacts.

## Android packaging is opt-in

No workflow builds an APK unless the repository variable
`ATOMIC_ANDROID_PACKAGING` is `enabled` (**Settings → Secrets and variables →
Actions → Variables**). It is unset during the current redesign phase, so:

- Flutter verification runs analysis, tests, source artwork checks and the
  artifact scans, skips the debug APK build, its APK artwork check and its
  upload, and records those steps as `deferred` in its proof (never as passed);
- Staging Android runs only the provenance parser tests on pull requests; its
  package isolation and signed staging APK jobs are skipped;
- Signed Android release skips the release build;
- Device acceptance builds still run the guarded bootstrap tests, in their
  own job, and skip the acceptance APK build and upload.

Each skipped workflow shows an "Android packaging deferred (no APK built)"
notice. Set the variable to `enabled` only when an APK is actually wanted.

`tool/check_workflow_packaging.py` (run by Flutter verification, with its
tests in `tool/test_check_workflow_packaging.py`) fails if any workflow step
that builds or uploads an APK, app bundle or APK set is not guarded by the
variable, so a new packaging step cannot slip in unguarded. A guard is a
strict allow-list: the job's or the step's `if:` is a conjunction of simple
comparisons that includes `vars.ATOMIC_ANDROID_PACKAGING == 'enabled'`.
Conditions with `||`, `!`, functions or comments do not count, and neither
does an `env.` comparison, because any earlier step or action can change
`env` through `$GITHUB_ENV`. The Flutter verification job still sets
`ATOMIC_ANDROID_PACKAGING` in its `env` from the variable, but only to tell
the deferred notice and the proof recorder which mode ran; the recorder
fails if that mode and the APK step outcomes disagree.

The checker reads every workflow against an explicit list of the keys and
indentation this repository uses (top-level, job and step keys, and block
`env:`, `with:`, `defaults:`, `strategy:` and `environment:` mappings).
Anything else fails the check (exit 2) instead of being skipped or read as
a job without steps: an unknown, duplicated or quoted key, other
indentation, inline mappings or flow collections (except a strategy matrix
list), a value continued where one line is expected, tabs or other line
breaks, a byte order mark, anchors, reusable jobs and local actions. A new
key or shape needs a reviewed change to the checker.

Values are decoded as YAML decodes them before they are inspected. Quoted
values are unquoted and their escapes decoded, so `run: "flutter\x20build apk"`
is a build and `uses: "./action"` is a local action. Block scalars keep their
YAML meaning: a literal block (`|`) keeps its lines, and a folded block (`>`)
joins ordinary lines with spaces, so a folded `gradle test` followed by
`build` is the single command `gradle test build`. Blank lines before the
first content line are kept as newlines, as YAML keeps them. The check fails instead of
guessing on a quoted value that does not close on its line, an unknown
escape, text after a closing quote, a block with an indentation indicator
(`|2`), a block line at an indentation YAML would not accept, and a plain
`run` value continued onto another line (write it as a block).

Any `gradle` or `gradlew` command in a step's `run` counts as packaging
unless every argument is a known non-packaging task or option (`test`,
`lint`, `clean`, `--version` and a few others). That list is a lexical rule:
it does not prove that a build script attaches no packaging work to a task
named `test` or `clean`.

It reads the workflow files only. A packaging command assembled at run time
or by shell quoting (for example `flutter "build" apk`), inside a script or
helper, inside a Gradle build script, or inside a third-party action is
outside what it can detect or prove. The verification proof also fails in
deferred mode if any Android package is found in the generated output
directories.

## Signed Android release

**Signed Android release** (`.github/workflows/release-android.yml`) is manual
only. It analyzes, tests, builds `--release --split-per-abi` APKs, checks that
none is signed with the Android debug key, and uploads them as a 14-day
workflow artifact. It publishes nothing: download the artifact and attach the
files to a GitHub Release yourself. It stops with an error, and never falls
back to the debug key, if any signing secret is missing.

One-time setup (do this on your own machine; never paste these values into a
chat or commit them):

1. Create a release key. Keep the file and both passwords somewhere safe:
   losing them means you can never update an installed app.
   ```bash
   keytool -genkeypair -v -keystore atomic-release.jks -alias atomic -keyalg RSA -keysize 2048 -validity 10000
   ```
2. Base64-encode it and add the four **secrets** under *Settings → Secrets and
   variables → Actions → Secrets*: `ANDROID_KEYSTORE_BASE64`,
   `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
   ```bash
   base64 -w0 atomic-release.jks
   ```
3. Add two **variables** (public values) under the *Variables* tab:
   `API_BASE_URL` (`https://atomic-notes-server-gde2e.vercel.app/api`) and
   `GOOGLE_SERVER_CLIENT_ID` (the Server's **Web** OAuth client ID).
4. Run **Actions → Signed Android release → Run workflow**. The job summary
   prints each APK's certificate **SHA-1**. Register that SHA-1 in the Google
   Cloud **Android** OAuth client for package `com.notes.atomic`, otherwise
   Google sign-in fails on the release build.

Nothing here has been run yet. The first run is the first proof that it works.

## Showcase site

**Deploy showcase site (GitHub Pages)** uploads only `docs/`. It does not
compile Flutter. Before running it, set **Settings → Pages → Build and
deployment → Source → GitHub Actions** in this repository. A missing Pages
site or inaccessible Pages configuration produces HTTP 404. If the setting
is unavailable, check repository visibility and plan eligibility.

See [GitHub's Pages setup instructions](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site).
Automatic enablement requires additional token permissions; this workflow
uses the default token and expects the owner to configure Pages first.

Server and Community typechecks now run in their own repositories. Require
successful runs for all three project commits before integration testing.
