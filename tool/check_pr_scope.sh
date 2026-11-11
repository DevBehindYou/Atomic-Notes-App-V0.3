#!/usr/bin/env bash
# Scope gate for UI/UX redesign checkpoints.
#
# Each checkpoint carries one scope label. This script fails when the
# checkpoint would touch a path that its label does not allow, so a styling
# change cannot quietly reach sync, storage, security or mascot code. The
# allowed paths come from the redesign blueprint (Functionality-Preservation
# section 4 and CI-CD-PR-Workflow section 3 in Revamp-UIUX/10-Implementation-
# Blueprint); keep the two in step.
#
# Usage: tool/check_pr_scope.sh <label> <base-ref> [--worktree]
#
#   label       foundation | component | state | page | legacy | rename | verify
#   base-ref    the last checkpoint commit or tag (for example ux/m0-baseline)
#   --worktree  also check unstaged and untracked files, to preview a change
#               before staging it
#
# Without --worktree it checks what the next commit would hold relative to
# <base-ref>: commits made since <base-ref> plus the staged index. Renames are
# split into a deletion and an addition, so both paths must be in scope.
#
# Exit status: 0 in scope, 1 out of scope, 2 usage or Git error.

set -euo pipefail

usage() {
  echo "usage: tool/check_pr_scope.sh <foundation|component|state|page|legacy|rename|verify> <base-ref> [--worktree]" >&2
  exit 2
}

[[ $# -ge 2 && $# -le 3 ]] || usage
label=$1
base=$2
mode=${3:-}
[[ -z $mode || $mode == --worktree ]] || usage

# Never allowed under any label. The blueprint treats a change here as a
# contract change that needs its own proposal, or the path belongs to another
# owner (lib/mascot is reserved by a Codex branch, ADR-008).
banned=(
  'lib/api/*'
  'lib/security/*'
  'lib/mascot/*'
  'lib/authentication/auth_services/*'
  'lib/editor/rich_text_controller.dart'
  'lib/editor/editor_media.dart'
  'lib/editor/note_image_decode.dart'
  'lib/utility/app_info.dart'
  'lib/utility/splash_route_resolver.dart'
  'lib/utility/web_links.dart'
  '*/cred.dart'
  'analysis_options.yaml'
  'android/*'
  'ios/*'
  'linux/*'
  'macos/*'
  'windows/*'
  'web/*'
  '.github/*'
)

case $label in
  foundation)
    # Tokens, themes, fonts, icons, motion tokens, appearance preference.
    # startup_sequence/startup_trace and their tests only for opening the
    # appearance box at startup (UX-01-appearance).
    allowed=(
      'lib/theme/*'
      'lib/appearance/*'
      'lib/main.dart'
      'lib/utility/startup_sequence.dart'
      'lib/utility/startup_trace.dart'
      'pubspec.yaml'
      'assets/fonts/*'
      'tool/*'
      'test/theme/*'
      'test/appearance/*'
      'test/support/themed.dart'
      'test/startup_*'
    )
    ;;
  component)
    # The design-system widgets; main.dart only to register the debug gallery.
    allowed=(
      'lib/ui/*'
      'lib/main.dart'
      'test/ui/*'
      'test/support/*'
    )
    ;;
  state)
    # The approved tag-filter and sort change (D3). notes_source.dart declares
    # the visible() signature that NotesRepository implements.
    allowed=(
      'lib/database/note.dart'
      'lib/database/notes_repository.dart'
      'lib/database/notes_source.dart'
      'lib/state/notes/*'
      'test/*'
    )
    ;;
  page)
    # Screen checkpoints (M3 to M8) and the accessibility sweep. Which page
    # files a checkpoint may touch is narrowed further by its matrix row,
    # which the reviewer checks.
    allowed=(
      'lib/page/*'
      'lib/editor/*'
      'lib/utility/component/*'
      'lib/utility/intropages/*'
      'lib/authentication/auth_pages/*'
      'lib/profile/*_page.dart'
      'lib/recovery/*_page.dart'
      'lib/recovery/import_preview_view.dart'
      'lib/platform/browser_preview_gate.dart'
      'lib/main.dart'
      'lib/ui/*'
      'test/*'
    )
    ;;
  legacy)
    # Removal of the old tokens, editorial kit, retired widgets, fonts and
    # packages (M9).
    allowed=(
      'lib/theme/*'
      'lib/utility/component/*'
      'lib/utility/intropages/*'
      'lib/main.dart'
      'pubspec.yaml'
      'pubspec.lock'
      'assets/fonts/*'
      'test/*'
    )
    ;;
  rename)
    # Mechanical class renames (UX-11), for example NotesBulder to NoteCard.
    allowed=(
      'lib/page/*'
      'lib/editor/*'
      'lib/utility/component/*'
      'lib/utility/intropages/*'
      'lib/authentication/auth_pages/*'
      'lib/ui/*'
      'lib/main.dart'
      'test/*'
    )
    ;;
  verify)
    # Measurement records, captures and their tooling.
    allowed=(
      'docs/*'
      'tool/*'
    )
    ;;
  *)
    echo "check_pr_scope: unknown label '$label'" >&2
    usage
    ;;
esac

cd "$(git rev-parse --show-toplevel)"
if ! git rev-parse --verify --quiet "$base^{commit}" >/dev/null; then
  echo "check_pr_scope: base '$base' is not a commit" >&2
  exit 2
fi

paths=()
while IFS= read -r -d '' p; do paths+=("$p"); done < <(
  git -c core.quotepath=off diff --cached --name-only --no-renames -z "$base"
  if [[ $mode == --worktree ]]; then
    git -c core.quotepath=off diff --name-only --no-renames -z "$base"
    git -c core.quotepath=off ls-files --others --exclude-standard -z
  fi
)

# Sort and drop duplicates (worktree mode lists staged paths twice).
unique=()
if [[ ${#paths[@]} -gt 0 ]]; then
  while IFS= read -r -d '' p; do unique+=("$p"); done < <(
    printf '%s\0' "${paths[@]}" | sort -zu
  )
fi

matches() {
  local path=$1
  shift
  local pattern
  for pattern in "$@"; do
    # shellcheck disable=SC2053  # the pattern is a glob on purpose
    [[ $path == $pattern ]] && return 0
  done
  return 1
}

failures=0
for p in ${unique[@]+"${unique[@]}"}; do
  if matches "$p" "${banned[@]}"; then
    echo "OUT OF SCOPE (never allowed): $p"
    failures=$((failures + 1))
  elif ! matches "$p" "${allowed[@]}"; then
    echo "OUT OF SCOPE (not allowed for '$label'): $p"
    failures=$((failures + 1))
  fi
done

if [[ $failures -gt 0 ]]; then
  echo "check_pr_scope: $failures of ${#unique[@]} path(s) outside '$label' since $base" >&2
  exit 1
fi
echo "check_pr_scope: ${#unique[@]} path(s) within '$label' since $base"
