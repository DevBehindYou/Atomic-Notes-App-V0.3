#!/usr/bin/env bash
# Self-test for tool/check_pr_scope.sh. Builds throwaway Git repositories in a
# temporary directory and checks pass, fail and operational-error results for
# every label, including the adversarial cases from the 11 November review.
# Touches nothing outside the temporary directory.
#
# Usage: tool/test_check_pr_scope.sh

set -euo pipefail

checker="$(cd "$(dirname "$0")" && pwd)/check_pr_scope.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Never let Git discovery escape the temporary directory (on some machines a
# parent directory, such as the home directory, is itself a repository).
export GIT_CEILING_DIRECTORIES=$work

passed=0
failed=0

git_t() { git -c user.name=scope-test -c user.email=scope-test@example.invalid -c core.autocrlf=false "$@"; }

# Fresh repository: the given paths plus README.seed committed and tagged "base".
new_repo() {
  local dir p
  dir=$(mktemp -d "$work/repo.XXXXXX")
  git_t -C "$dir" init -q
  for p in "$@"; do
    mkdir -p "$dir/$(dirname "$p")"
    echo seed >"$dir/$p"
  done
  echo seed >"$dir/README.seed"
  git_t -C "$dir" add -A
  git_t -C "$dir" commit -q -m base
  git_t -C "$dir" tag base
  echo "$dir"
}

# expect <name> <expected-exit> <dir> <checker args...>
expect() {
  local name=$1 want=$2 dir=$3 got=0
  shift 3
  (cd "$dir" && "$checker" "$@" >/dev/null 2>&1) || got=$?
  if [[ $got == "$want" ]]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    echo "FAIL: $name (expected exit $want, got $got)"
  fi
}

# stage <dir> <path...>: create or change each path and stage it.
stage() {
  local dir=$1 p
  shift
  for p in "$@"; do
    mkdir -p "$dir/$(dirname "$p")"
    echo change >>"$dir/$p"
    git_t -C "$dir" add -- "$p"
  done
}

# put <dir> <path> <content>: write exact content and stage it.
put() {
  mkdir -p "$1/$(dirname "$2")"
  printf '%s' "$3" >"$1/$2"
  git_t -C "$1" add -- "$2"
}

# case_staged <name> <label> <expected-exit> <path...>
case_staged() {
  local name=$1 label=$2 want=$3 dir
  shift 3
  dir=$(new_repo)
  stage "$dir" "$@"
  expect "$name" "$want" "$dir" "$label" base
}

# case_manifest <name> <label> <expected-exit> <manifest-lines> <path...>
case_manifest() {
  local name=$1 label=$2 want=$3 lines=$4 dir
  shift 4
  dir=$(new_repo)
  stage "$dir" "$@"
  printf '%s\n' "$lines" >"$dir.manifest"
  expect "$name" "$want" "$dir" "$label" base --allow-file "$dir.manifest"
}

# ---- allowed paths pass --------------------------------------------------------

case_staged 'foundation theme+fonts+tests' foundation 0 lib/theme/atomic_colors.dart assets/fonts/Figtree-Regular.ttf test/theme/atomic_colors_test.dart
case_staged 'foundation appearance startup' foundation 0 lib/appearance/appearance_controller.dart lib/utility/startup_sequence.dart test/startup_sequence_test.dart test/support/themed.dart
case_staged 'foundation icon generator' foundation 0 tool/generate_atomic_icons.py
case_staged 'component ui' component 0 lib/ui/buttons/atomic_button.dart test/ui/atomic_button_test.dart lib/main.dart
case_staged 'state named tests' state 0 lib/database/note.dart lib/database/notes_source.dart lib/state/notes/notes_bloc.dart test/notes_bloc_test.dart test/support/fake_notes_source.dart
case_staged 'page home' page 0 lib/page/home_page.dart lib/utility/component/notes_builder.dart lib/ui/cards/note_card.dart test/ui/note_card_test.dart
case_staged 'page gated views' page 0 lib/profile/guest_workspace_page.dart lib/recovery/recovery_page.dart lib/recovery/import_preview_view.dart lib/platform/browser_preview_gate.dart
case_staged 'page editor views' page 0 lib/editor/editor_popup.dart lib/editor/note_image_viewer.dart lib/editor/rich_selection_toolbar.dart lib/page/notes_editor_page.dart
case_staged 'legacy removal' legacy 0 lib/theme/editorial.dart pubspec.yaml pubspec.lock assets/fonts/BebasNeue-Regular.ttf
case_staged 'verify docs' verify 0 docs/ux/measurement.md
case_staged 'gate files' gate 0 tool/check_pr_scope.sh tool/test_check_pr_scope.sh
case_staged 'path with spaces' page 0 'lib/page/endpage/a b_page.dart'
case_staged 'leading dash basename' page 0 'lib/page/-odd_page.dart'
case_manifest 'page test via manifest' page 0 'test/home_page_test.dart' lib/page/home_page.dart test/home_page_test.dart
case_manifest 'rename test via manifest' rename 0 $'# reviewed\ntest/widget_test.dart' lib/utility/component/notes_builder.dart test/widget_test.dart
case_manifest 'verify tool via manifest' verify 0 'tool/ux_frame_timing.py' docs/m.md tool/ux_frame_timing.py

# ---- forbidden paths fail ------------------------------------------------------

case_staged 'foundation touches page' foundation 1 lib/theme/atomic_colors.dart lib/page/home_page.dart
case_staged 'foundation touches lockfile' foundation 1 pubspec.lock
case_staged 'foundation CI proof tool' foundation 1 tool/run_web_compile_proof.py
case_staged 'foundation touches gate' foundation 1 tool/check_pr_scope.sh
case_staged 'verify CI scanner tool' verify 1 tool/scan_ci_artifacts.py
case_staged 'verify unlisted tool' verify 1 tool/ux_frame_timing.py
case_staged 'gate touches lib' gate 1 tool/check_pr_scope.sh lib/theme/a.dart
case_staged 'component touches page' component 1 lib/ui/x.dart lib/page/settings_page.dart
case_staged 'component other test helper' component 1 lib/ui/x.dart test/support/fake_other.dart
case_staged 'state unrelated test' state 1 lib/state/notes/notes_bloc.dart test/energy_test.dart
case_staged 'state touches page' state 1 lib/state/notes/notes_bloc.dart lib/page/home_page.dart
case_staged 'state touches other cubit' state 1 lib/state/energy/energy_cubit.dart
case_staged 'state touches sync policy' state 1 lib/database/sync_policy.dart
case_staged 'page touches state' page 1 lib/page/home_page.dart lib/state/notes/notes_state.dart
case_staged 'page test without manifest' page 1 lib/page/home_page.dart test/home_page_test.dart
case_staged 'page touches pubspec' page 1 lib/page/home_page.dart pubspec.yaml
case_staged 'page new editor logic file' page 1 lib/editor/new_logic.dart
case_staged 'page touches recovery logic' page 1 lib/recovery/restore_coordinator.dart
case_staged 'page touches recovery panel file' page 1 lib/recovery/recovery_diagnostics.dart
case_staged 'page touches profile store' page 1 lib/profile/profile_store.dart
case_staged 'mascot is banned' page 1 lib/mascot/mascot_view.dart
case_staged 'mascot banned for rename' rename 1 lib/mascot/mascot_view.dart
case_staged 'security is banned' foundation 1 lib/security/vault.dart
case_staged 'api is banned' page 1 lib/api/api_client.dart
case_staged 'editor logic is banned' page 1 lib/editor/rich_text_controller.dart
case_staged 'auth services banned' page 1 lib/authentication/auth_services/session_guard.dart
case_staged 'registrants banned' foundation 1 windows/flutter/generated_plugin_registrant.cc
case_staged 'workflow banned' verify 1 .github/workflows/ux-gates.yml
case_staged 'cred banned' foundation 1 lib/theme/cred.dart
case_staged 'verify touches lib' verify 1 lib/theme/atomic_colors.dart
case_manifest 'manifest cannot unban' state 1 'test/sync_conflict_preservation_test.dart' test/sync_conflict_preservation_test.dart

# ---- manifest misuse is an error -----------------------------------------------

case_manifest 'manifest wildcard' page 2 'test/*' lib/page/home_page.dart
case_manifest 'manifest outside test' page 2 'lib/state/notes/notes_bloc.dart' lib/page/home_page.dart
case_manifest 'manifest CI tool for verify' verify 2 'tool/scan_ci_artifacts.py' docs/m.md
case_manifest 'gate refuses manifest' gate 2 'test/a_test.dart' tool/check_pr_scope.sh
dir=$(new_repo)
expect 'manifest missing file' 2 "$dir" page base --allow-file "$work/no-such-manifest"

# ---- deletions, renames, history -----------------------------------------------

dir=$(new_repo lib/state/notes/notes_event.dart)
git_t -C "$dir" rm -q lib/state/notes/notes_event.dart
expect 'page deletes state file' 1 "$dir" page base

dir=$(new_repo lib/page/old_page.dart)
mkdir -p "$dir/lib/database"
git_t -C "$dir" mv lib/page/old_page.dart lib/database/old_page.dart
expect 'rename into database' 1 "$dir" page base

dir=$(new_repo)
stage "$dir" lib/page/home_page.dart
git_t -C "$dir" commit -q -m one
stage "$dir" lib/state/notes/notes_bloc.dart
git_t -C "$dir" commit -q -m two
expect 'committed out-of-scope since base' 1 "$dir" page base

# ---- work tree mode --------------------------------------------------------------

dir=$(new_repo)
stage "$dir" lib/theme/atomic_type.dart
mkdir -p "$dir/lib/page"
echo draft >"$dir/lib/page/home_page.dart"
expect 'untracked ignored without --worktree' 0 "$dir" foundation base
expect 'untracked caught with --worktree' 1 "$dir" foundation base --worktree

dir=$(new_repo lib/state/notes/notes_bloc.dart)
stage "$dir" lib/state/notes/notes_bloc.dart
git_t -C "$dir" show base:lib/state/notes/notes_bloc.dart >"$dir/lib/state/notes/notes_bloc.dart"
expect 'staged forbidden + unstaged revert' 1 "$dir" page base --worktree
expect 'staged forbidden, index mode' 1 "$dir" page base

# ---- entry types and unusual names -----------------------------------------------

dir=$(new_repo)
blob=$(printf 'target' | git_t -C "$dir" hash-object -w --stdin)
git_t -C "$dir" update-index --add --cacheinfo "120000,$blob,lib/ui/link.dart"
expect 'symlink entry rejected' 1 "$dir" component base

dir=$(new_repo)
head=$(git_t -C "$dir" rev-parse HEAD)
git_t -C "$dir" update-index --add --cacheinfo "160000,$head,lib/ui/sub"
expect 'submodule entry rejected' 1 "$dir" component base

# Git for Windows refuses tabs and newlines in paths unless NTFS protection is
# off; Linux Git allows them. These index-only entries never reach the disk.
dir=$(new_repo)
git_t -C "$dir" config core.protectNTFS false
blob=$(printf 'x' | git_t -C "$dir" hash-object -w --stdin)
git_t -C "$dir" update-index --add --cacheinfo "100644,$blob,lib/ui/a"$'\t'"b.dart"
expect 'tab in allowed name' 0 "$dir" component base

dir=$(new_repo)
git_t -C "$dir" config core.protectNTFS false
blob=$(printf 'x' | git_t -C "$dir" hash-object -w --stdin)
git_t -C "$dir" update-index --add --cacheinfo "100644,$blob,lib/ui/ok.dart"
git_t -C "$dir" update-index --add --cacheinfo "100644,$blob,lib/api/x"$'\n'"y.dart"
expect 'newline in forbidden name' 1 "$dir" component base

# ---- region rules: NotesRepository.visible() and pubspec fonts --------------------

repo_src='class NotesRepository {
  int get count => 0;

  /// Live notes.
  @override
  List<Note> visible({NoteFilter filter = NoteFilter.newest}) {
    final list = <Note>[];
    if (filter == NoteFilter.oldest) {
      list.sort((a, b) => a.compareTo(b)); // "}" in a comment
    }
    return list;
  }

  int get pendingCount => 0;
}
'
region_repo() {
  local dir
  dir=$(mktemp -d "$work/repo.XXXXXX")
  git_t -C "$dir" init -q
  put "$dir" lib/database/notes_repository.dart "$repo_src"
  put "$dir" pubspec.yaml 'name: app
dependencies:
  flutter:
    sdk: flutter
flutter:
  uses-material-design: true
  assets:
    - assets/
  fonts:
    - family: Old
      fonts:
        - asset: assets/fonts/Old.ttf
'
  git_t -C "$dir" commit -q -m base
  git_t -C "$dir" tag base
  echo "$dir"
}

# edit_repo <dir> <literal-text> <replacement>: rewrite the fixture repository.
edit_repo() {
  put "$1" lib/database/notes_repository.dart "${repo_src/"$2"/"$3"}"
}

dir=$(region_repo)
edit_repo "$dir" 'final list = <Note>[];' 'final list = <Note>[]; // edited'
expect 'visible() body edit' 0 "$dir" state base

dir=$(region_repo)
edit_repo "$dir" '/// Live notes.' '/// Live notes, pinned first.'
expect 'visible() doc comment edit' 0 "$dir" state base

dir=$(region_repo)
edit_repo "$dir" 'int get count => 0;' 'int get count => 1;'
expect 'other repository member' 1 "$dir" state base

dir=$(region_repo)
edit_repo "$dir" '  int get pendingCount' $'  void extra() {}\n\n  int get pendingCount'
expect 'new repository method' 1 "$dir" state base

dir=$(region_repo)
edit_repo "$dir" 'visible({' 'shown({'
expect 'visible() renamed away' 1 "$dir" state base

dir=$(region_repo)
edit_repo "$dir" $'    return list;\n  }\n' $'    return list;\n  }\n  int leak = 0;\n'
expect 'line right after visible() brace' 1 "$dir" state base

dir=$(region_repo)
edit_repo "$dir" '  /// Live notes.' $'  /// Extra doc line.\n  /// Live notes.'
expect 'doc line added above visible()' 0 "$dir" state base

dir=$(region_repo)
edit_repo "$dir" $'  int get count => 0;\n' ''
expect 'line removed before visible()' 1 "$dir" state base

dir=$(region_repo)
git_t -C "$dir" rm -q lib/database/notes_repository.dart
expect 'repository deleted' 1 "$dir" state base

dir=$(region_repo)
printf '\n    - family: Figtree\n      fonts:\n        - asset: assets/fonts/Figtree-Regular.ttf\n' >>"$dir/pubspec.yaml"
git_t -C "$dir" add pubspec.yaml
expect 'pubspec fonts addition' 0 "$dir" foundation base

dir=$(region_repo)
sed 's/uses-material-design: true/uses-material-design: false/' "$dir/pubspec.yaml" >"$dir/p" && mv "$dir/p" "$dir/pubspec.yaml"
git_t -C "$dir" add pubspec.yaml
expect 'pubspec non-font edit' 1 "$dir" foundation base

dir=$(region_repo)
printf 'extra_key: true\n' >>"$dir/pubspec.yaml"
git_t -C "$dir" add pubspec.yaml
expect 'pubspec new top-level key' 1 "$dir" foundation base

dir=$(region_repo)
sed 's/^  flutter:$/  flutter:\n  http: any/' "$dir/pubspec.yaml" >"$dir/p" && mv "$dir/p" "$dir/pubspec.yaml"
git_t -C "$dir" add pubspec.yaml
expect 'pubspec dependency added' 1 "$dir" foundation base

# ---- base validation ---------------------------------------------------------------

dir=$(new_repo)
git_t -C "$dir" checkout -q -b side
stage "$dir" lib/ui/side.dart
git_t -C "$dir" commit -q -m side
git_t -C "$dir" tag side-tip
git_t -C "$dir" checkout -q -
stage "$dir" lib/ui/main.dart
git_t -C "$dir" commit -q -m main
expect 'non-ancestor base' 2 "$dir" component side-tip
expect 'ancestor base' 0 "$dir" component base

dir=$(new_repo)
expect 'option-like base' 2 "$dir" component "--output=$work/pwned"
if [[ -e $work/pwned ]]; then failed=$((failed + 1)); echo "FAIL: option-like base wrote a file"; else passed=$((passed + 1)); fi

dir=$(new_repo)
echo not-a-ref >"$dir/base"
expect 'ref and file share a name' 0 "$dir" component base

# ---- operational failures fail closed -----------------------------------------------

dir=$(new_repo)
stage "$dir" lib/page/home_page.dart
printf 'not an index' >"$dir/.git/index"
expect 'corrupt index (staged mode)' 2 "$dir" page base
expect 'corrupt index (worktree mode)' 2 "$dir" page base --worktree

mkdir -p "$work/plain"
expect 'not a repository' 2 "$work/plain" page base

dir=$(new_repo)
stage "$dir" lib/page/home_page.dart
mkdir -p "$work/fakebin"
printf '#!/bin/sh\nexit 3\n' >"$work/fakebin/sort"
chmod +x "$work/fakebin/sort"
got=0
(cd "$dir" && PATH="$work/fakebin:$PATH" "$checker" page base >/dev/null 2>&1) || got=$?
if [[ $got == 2 ]]; then passed=$((passed + 1)); else failed=$((failed + 1)); echo "FAIL: failing sort (expected exit 2, got $got)"; fi

dir=$(new_repo lib/page/home_page.dart)
git_t -C "$dir" checkout -q -b other
echo other >"$dir/lib/page/home_page.dart"
git_t -C "$dir" commit -qam other
git_t -C "$dir" checkout -q -
echo mine >"$dir/lib/page/home_page.dart"
git_t -C "$dir" commit -qam mine
git_t -C "$dir" merge -q other >/dev/null 2>&1 || true
expect 'unmerged index' 2 "$dir" page base

# ---- usage errors ---------------------------------------------------------------------

dir=$(new_repo)
expect 'unknown label' 2 "$dir" styling base
expect 'unknown base' 2 "$dir" page no-such-ref
expect 'bad option' 2 "$dir" page base --all
expect 'missing base' 2 "$dir" page
expect 'empty diff' 0 "$dir" foundation base

# ---- the checker's own tree mode (only when run from a repository) --------------------

if mode=$(git -C "$(dirname "$checker")" ls-files -s -- check_pr_scope.sh test_check_pr_scope.sh 2>/dev/null) && [[ -n $mode ]]; then
  if grep -qv '^100755 ' <<<"$mode"; then
    failed=$((failed + 1)); echo "FAIL: tracked mode is not 100755:"; echo "$mode"
  else
    passed=$((passed + 1))
  fi
else
  echo "note: checker not tracked here; tree-mode check skipped"
fi

echo "test_check_pr_scope: $passed passed, $failed failed"
[[ $failed -eq 0 ]]
