#!/usr/bin/env bash
# Self-test for tool/check_pr_scope.sh. Builds throwaway Git repositories in a
# temporary directory and checks that in-scope changes pass and out-of-scope
# changes fail for every label. Touches nothing outside the temporary
# directory.
#
# Usage: tool/test_check_pr_scope.sh

set -euo pipefail

checker="$(cd "$(dirname "$0")" && pwd)/check_pr_scope.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

passed=0
failed=0

git_t() { git -c user.name=scope-test -c user.email=scope-test@example.invalid -c core.autocrlf=false "$@"; }

# Fresh repository with one committed file per path given, tagged "base".
new_repo() {
  local dir
  dir=$(mktemp -d "$work/repo.XXXXXX")
  git_t -C "$dir" init -q
  local p
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
  local name=$1 want=$2 dir=$3
  shift 3
  local got=0
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
  local dir=$1
  shift
  local p
  for p in "$@"; do
    mkdir -p "$dir/$(dirname "$p")"
    echo change >>"$dir/$p"
    git_t -C "$dir" add -- "$p"
  done
}

# case_staged <name> <label> <expected-exit> <path...>
case_staged() {
  local name=$1 label=$2 want=$3
  shift 3
  local dir
  dir=$(new_repo)
  stage "$dir" "$@"
  expect "$name" "$want" "$dir" "$label" base
}

# Allowed paths pass.
case_staged 'foundation theme+fonts+pubspec' foundation 0 lib/theme/atomic_colors.dart assets/fonts/Figtree-Regular.ttf pubspec.yaml test/theme/atomic_colors_test.dart
case_staged 'foundation appearance startup' foundation 0 lib/appearance/appearance_controller.dart lib/utility/startup_sequence.dart test/startup_sequence_test.dart test/support/themed.dart
case_staged 'component ui' component 0 lib/ui/buttons/atomic_button.dart test/ui/atomic_button_test.dart lib/main.dart
case_staged 'state D3 files' state 0 lib/database/note.dart lib/database/notes_repository.dart lib/database/notes_source.dart lib/state/notes/notes_bloc.dart test/notes_bloc_test.dart
case_staged 'page home' page 0 lib/page/home_page.dart lib/utility/component/notes_builder.dart lib/ui/cards/note_card.dart test/home_page_test.dart
case_staged 'page gated views' page 0 lib/profile/guest_workspace_page.dart lib/recovery/recovery_page.dart lib/recovery/import_preview_view.dart lib/platform/browser_preview_gate.dart
case_staged 'page editor view' page 0 lib/editor/editor_popup.dart lib/page/notes_editor_page.dart
case_staged 'legacy removal' legacy 0 lib/theme/editorial.dart pubspec.yaml pubspec.lock assets/fonts/BebasNeue-Regular.ttf
case_staged 'rename' rename 0 lib/utility/component/notes_builder.dart lib/page/home_page.dart test/widget_test.dart
case_staged 'verify docs' verify 0 docs/ux/measurement.md tool/frame_timing.sh
case_staged 'path with spaces' page 0 'lib/page/endpage/a b_page.dart'

# Forbidden paths fail.
case_staged 'foundation touches page' foundation 1 lib/theme/atomic_colors.dart lib/page/home_page.dart
case_staged 'foundation touches lockfile' foundation 1 pubspec.lock
case_staged 'component touches page' component 1 lib/ui/x.dart lib/page/settings_page.dart
case_staged 'state touches page' state 1 lib/state/notes/notes_bloc.dart lib/page/home_page.dart
case_staged 'state touches other cubit' state 1 lib/state/energy/energy_cubit.dart
case_staged 'state touches sync policy' state 1 lib/database/sync_policy.dart
case_staged 'page touches state' page 1 lib/page/home_page.dart lib/state/notes/notes_state.dart
case_staged 'page touches pubspec' page 1 lib/page/home_page.dart pubspec.yaml
case_staged 'page touches recovery logic' page 1 lib/recovery/restore_coordinator.dart
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

# Deleting or renaming into a forbidden path fails.
dir=$(new_repo lib/state/notes/notes_event.dart)
git_t -C "$dir" rm -q lib/state/notes/notes_event.dart
expect 'page deletes state file' 1 "$dir" page base

dir=$(new_repo lib/page/old_page.dart)
mkdir -p "$dir/lib/database"
git_t -C "$dir" mv lib/page/old_page.dart lib/database/old_page.dart
expect 'rename into database' 1 "$dir" page base

# Commits since base count, not only the index.
dir=$(new_repo)
stage "$dir" lib/page/home_page.dart
git_t -C "$dir" commit -q -m one
stage "$dir" lib/state/notes/notes_bloc.dart
git_t -C "$dir" commit -q -m two
expect 'committed out-of-scope since base' 1 "$dir" page base

# Unstaged and untracked files count only with --worktree.
dir=$(new_repo)
stage "$dir" lib/theme/atomic_type.dart
mkdir -p "$dir/lib/page"
echo draft >"$dir/lib/page/home_page.dart"
expect 'untracked ignored without --worktree' 0 "$dir" foundation base
expect 'untracked caught with --worktree' 1 "$dir" foundation base --worktree

# Nothing changed passes.
dir=$(new_repo)
expect 'empty diff' 0 "$dir" foundation base

# Usage errors.
dir=$(new_repo)
expect 'unknown label' 2 "$dir" styling base
expect 'unknown base' 2 "$dir" page no-such-ref
expect 'bad option' 2 "$dir" page base --all
expect 'missing base' 2 "$dir" page

echo "test_check_pr_scope: $passed passed, $failed failed"
[[ $failed -eq 0 ]]
