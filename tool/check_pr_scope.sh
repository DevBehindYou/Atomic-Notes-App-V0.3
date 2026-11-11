#!/usr/bin/env bash
# Scope gate for UI/UX redesign checkpoints.
#
# Each checkpoint carries one scope label. This script fails when the
# checkpoint would touch a path, or a region of a file, that its label does
# not allow, so a styling change cannot quietly reach sync, storage, security,
# mascot, CI-proof or platform code. The rules follow the redesign blueprint
# (Revamp-UIUX/10-Implementation-Blueprint/Functionality-Preservation.md
# section 4) and the coordinator review of 11 November 2026; keep them in step.
#
# Usage:
#   tool/check_pr_scope.sh <label> <base-ref> [--worktree] [--allow-file FILE]
#
#   label         foundation | component | state | page | legacy | rename |
#                 verify | gate
#   base-ref      the last ACCEPTED checkpoint (commit or tag). It must be an
#                 ancestor of HEAD. Check it against the handoff record:
#                 ancestry alone cannot prove the right checkpoint was chosen.
#   --worktree    also check unstaged and untracked files (preview before
#                 staging). Staged content is always checked as well.
#   --allow-file  a reviewed manifest of extra exact paths for this
#                 checkpoint, one per line ('#' comments allowed). Entries
#                 must be under test/ (or tool/ux_ for verify) and contain no
#                 wildcards. A manifest never overrides the never-allowed list.
#
# Without --worktree it checks base..index: the commits since <base-ref> plus
# the staged changes. That is the net proposed tree; changes made and undone
# in intermediate commits are not visible to it, so reviewers also read the
# commit list it prints.
#
# Exit status: 0 in scope, 1 out of scope, 2 usage or operational error
# (including any Git, sort or file failure: the gate fails closed).
#
# Supported environment: Bash 4.4+ with GNU coreutils (Linux CI runners, Git
# Bash on Windows). macOS /bin/bash 3.2 and BSD sort are not supported.

set -euo pipefail

die() {
  echo "check_pr_scope: $*" >&2
  exit 2
}

usage() {
  echo "usage: tool/check_pr_scope.sh <foundation|component|state|page|legacy|rename|verify|gate> <base-ref> [--worktree] [--allow-file FILE]" >&2
  exit 2
}

# ---- arguments ---------------------------------------------------------------

[[ $# -ge 2 ]] || usage
label=$1
base=$2
shift 2
worktree=false
manifest=
while [[ $# -gt 0 ]]; do
  case $1 in
    --worktree) worktree=true ;;
    --allow-file)
      [[ $# -ge 2 && -n $2 ]] || usage
      [[ -f $2 ]] || die "manifest '$2' is not a file"
      manifest="$(cd "$(dirname -- "$2")" && pwd)/$(basename -- "$2")" || die "cannot resolve manifest '$2'"
      shift
      ;;
    *) usage ;;
  esac
  shift
done
[[ $base != -* && -n $base ]] || die "base '$base' looks like an option; pass a commit or tag"

# ---- rules -------------------------------------------------------------------

# Never allowed under any label: contract changes needing their own proposal,
# or paths reserved for another owner (lib/mascot and the durability test are
# Codex's; the D3 release covers NotesRepository.visible() only).
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
  'lib/recovery/recovery_diagnostics.dart'
  'test/sync_conflict_preservation_test.dart'
  'test/mascot/mascot_view_test.dart'
  '*cred.dart'
  'analysis_options.yaml'
  'android/*'
  'ios/*'
  'linux/*'
  'macos/*'
  'windows/*'
  'web/*'
  '.github/*'
)

# Presentation files a page or rename checkpoint may touch. Named, not
# wildcarded, where a directory also holds logic.
presentation=(
  'lib/page/*'
  'lib/editor/editor_popup.dart'
  'lib/editor/note_image_viewer.dart'
  'lib/editor/rich_selection_toolbar.dart'
  'lib/utility/component/*'
  'lib/utility/intropages/*'
  'lib/authentication/auth_pages/*'
  'lib/profile/guest_workspace_page.dart'
  'lib/recovery/recovery_page.dart'
  'lib/recovery/import_preview_view.dart'
  'lib/platform/browser_preview_gate.dart'
  'lib/ui/*'
  'test/ui/*'
)

declare -A region=()     # path -> rule the changed lines must stay inside
review=()                # whole-file permissions whose hunks need human review
manifest_ok=true
manifest_prefix='test/'

case $label in
  foundation)
    allowed=(
      'lib/theme/*'
      'lib/appearance/*'
      'lib/main.dart'
      'lib/utility/startup_sequence.dart'
      'lib/utility/startup_trace.dart'
      'pubspec.yaml'
      'assets/fonts/*'
      'tool/generate_atomic_icons.py'
      'test/theme/*'
      'test/appearance/*'
      'test/support/themed.dart'
      'test/startup_sequence_test.dart'
      'test/startup_trace_test.dart'
    )
    region['pubspec.yaml']='yaml-block:fonts'
    review=('lib/main.dart' 'lib/utility/startup_sequence.dart' 'lib/utility/startup_trace.dart')
    ;;
  component)
    allowed=('lib/ui/*' 'lib/main.dart' 'test/ui/*' 'test/support/themed.dart')
    review=('lib/main.dart')
    ;;
  state)
    # The approved tag-filter and sort change (D3).
    allowed=(
      'lib/database/note.dart'
      'lib/database/notes_repository.dart'
      'lib/database/notes_source.dart'
      'lib/state/notes/*'
      'test/notes_bloc_test.dart'
      'test/notes_filter_test.dart'
      'test/search_correctness_test.dart'
      'test/mixed_note_home_test.dart'
      'test/mixed_note_persistence_test.dart'
      'test/notes_repository_lifecycle_test.dart'
      'test/rich_note_persistence_test.dart'
      'test/support/fake_notes_source.dart'
    )
    region['lib/database/notes_repository.dart']='dart-method:visible'
    ;;
  page)
    allowed=("${presentation[@]}" 'lib/main.dart')
    review=('lib/main.dart')
    ;;
  legacy)
    allowed=(
      'lib/theme/*'
      'lib/utility/component/*'
      'lib/utility/intropages/*'
      'lib/main.dart'
      'pubspec.yaml'
      'pubspec.lock'
      'assets/fonts/*'
    )
    review=('lib/main.dart' 'pubspec.yaml' 'pubspec.lock')
    ;;
  rename)
    allowed=("${presentation[@]}" 'lib/main.dart')
    review=('lib/main.dart')
    ;;
  verify)
    allowed=('docs/*')
    manifest_prefix='test/|tool/ux_'
    ;;
  gate)
    # The checker and its self-test change only in their own checkpoints,
    # each reviewed independently: a repository-local allow-list is not a
    # security boundary against its own author.
    allowed=('tool/check_pr_scope.sh' 'tool/test_check_pr_scope.sh')
    manifest_ok=false
    ;;
  *)
    echo "check_pr_scope: unknown label '$label'" >&2
    usage
    ;;
esac

matches() {
  local path=$1 pattern
  shift
  for pattern in "$@"; do
    # shellcheck disable=SC2053  # the pattern is a glob on purpose
    [[ $path == $pattern ]] && return 0
  done
  return 1
}

# ---- repository and base -----------------------------------------------------

top=$(git rev-parse --show-toplevel) || die "not inside a Git work tree"
[[ -n $top ]] || die "not inside a Git work tree"
cd "$top" || die "cannot enter $top"

base_oid=$(git rev-parse --verify --quiet --end-of-options "${base}^{commit}") ||
  die "base '$base' is not a commit"
head_oid=$(git rev-parse --verify --quiet --end-of-options 'HEAD^{commit}') ||
  die "HEAD is not a commit"
rc=0
git merge-base --is-ancestor "$base_oid" "$head_oid" || rc=$?
case $rc in
  0) ;;
  1) die "base '$base' ($base_oid) is not an ancestor of HEAD" ;;
  *) die "git merge-base failed ($rc)" ;;
esac

tmp=$(mktemp -d) || die "mktemp failed"
trap 'rm -rf -- "$tmp"' EXIT

commits=$(git log --format='  %h %s' "$base_oid..$head_oid") || die "git log failed"

# ---- manifest ----------------------------------------------------------------

extra=()
if [[ -n $manifest ]]; then
  $manifest_ok || die "label '$label' does not accept --allow-file"
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    [[ -z ${line//[[:space:]]/} || $line == \#* ]] && continue
    [[ $line != *[\*\?\[]* ]] || die "manifest entry has a wildcard: $line"
    [[ $line =~ ^($manifest_prefix) ]] || die "manifest entry outside ${manifest_prefix//|/ or }: $line"
    extra+=("$line")
  done <"$manifest" || die "cannot read manifest"
fi

# ---- enumerate changed paths (fail closed) -----------------------------------

: >"$tmp/paths" || die "cannot write temp file"
: >"$tmp/badtype" || die "cannot write temp file"

# Reads `git diff --raw -z` output: a ":oldmode newmode oldsha newsha status"
# record followed by one path (renames are split by --no-renames).
collect_raw() {
  local file=$1 meta path om nm st
  while IFS= read -r -d '' meta; do
    IFS= read -r -d '' path || die "truncated diff output"
    [[ $meta == :* ]] || die "unexpected diff record: $meta"
    read -r om nm _ _ st <<<"${meta#:}" || die "unreadable diff record: $meta"
    [[ $st != U* ]] || die "unmerged index entry: $path (finish or abort the merge first)"
    printf '%s\0' "$path" >>"$tmp/paths" || die "cannot write temp file"
    if [[ $om == 120000 || $nm == 120000 || $om == 160000 || $nm == 160000 ]]; then
      printf '%s\0' "$path" >>"$tmp/badtype" || die "cannot write temp file"
    fi
  done <"$file"
}

git diff --cached --raw -z --no-renames --no-ext-diff "$base_oid" -- >"$tmp/staged" ||
  die "git diff --cached failed (unreadable index?)"
collect_raw "$tmp/staged"

if $worktree; then
  git diff --raw -z --no-renames --no-ext-diff "$base_oid" -- >"$tmp/work" ||
    die "git diff (working tree) failed"
  collect_raw "$tmp/work"
  git ls-files --others --exclude-standard -z >"$tmp/untracked" ||
    die "git ls-files failed"
  while IFS= read -r -d '' p; do
    printf '%s\0' "$p" >>"$tmp/paths" || die "cannot write temp file"
    [[ -L $p ]] && { printf '%s\0' "$p" >>"$tmp/badtype" || die "cannot write temp file"; }
  done <"$tmp/untracked"
fi

sort -zu "$tmp/paths" >"$tmp/sorted" || die "sort failed"

declare -A bad=()
while IFS= read -r -d '' p; do bad[$p]=1; done <"$tmp/badtype"

paths=()
while IFS= read -r -d '' p; do paths+=("$p"); done <"$tmp/sorted"

# ---- region checks -----------------------------------------------------------

# Prints "start end" of the region a rule names in a file, or nothing.
# dart-method:NAME  a class member declared at two-space indentation, with its
#                   directly preceding doc comments and annotations, through
#                   its matching closing brace
# yaml-block:KEY    a two-space-indented YAML key and its nested lines
region_bounds() {
  local rule=$1 file=$2
  awk -v mode="${rule%%:*}" -v name="${rule#*:}" '
    function code(line,   out, i, c, q, n) {
      out = ""; q = ""; n = length(line)
      for (i = 1; i <= n; i++) {
        c = substr(line, i, 1)
        if (q != "") { if (c == "\\") { i++; continue } if (c == q) q = ""; continue }
        if (c == "\047" || c == "\"") { q = c; continue }
        if (c == "/" && substr(line, i + 1, 1) == "/") break
        out = out c
      }
      return out
    }
    { lines[NR] = $0 }
    END {
      s = 0; e = 0
      if (mode == "dart-method") {
        for (i = 1; i <= NR; i++) if (lines[i] ~ ("^  [^ /].*[ ]" name "[ ]*\\(")) { s = i; break }
        if (!s) exit 3
        depth = 0; seen = 0
        for (i = s; i <= NR; i++) {
          t = code(lines[i]); o = gsub(/\{/, "{", t); c = gsub(/\}/, "}", t)
          depth += o - c; if (o > 0) seen = 1
          if (seen && depth <= 0) { e = i; break }
        }
        if (!e) exit 3
        while (s > 1 && lines[s - 1] ~ /^  (\/\/\/|@)/) s--
      } else if (mode == "yaml-block") {
        for (i = 1; i <= NR; i++) if (lines[i] ~ ("^  " name ":[ \t]*$")) { s = i; break }
        if (!s) exit 3
        e = NR
        for (i = s + 1; i <= NR; i++) {
          l = lines[i]
          if (l ~ /^[ \t]*$/ || l ~ /^[ \t]*#/) continue
          match(l, /^ */); if (RLENGTH <= 2) { e = i - 1; break }
        }
      } else exit 4
      print s, e
    }' "$file"
}

# Fails (returns 1) unless every changed line between the base version and
# the given new version lies inside the rule's region in both versions.
check_region() {
  local path=$1 rule=$2 newsrc=$3 old=$tmp/region-old new=$tmp/region-new
  local ob nb os oe ns ne rc line a b c d
  git cat-file -e "$base_oid:$path" 2>/dev/null || return 1   # new file: no region in base
  git show "$base_oid:$path" >"$old.raw" || die "git show failed for base:$path"
  if [[ $newsrc == index ]]; then
    git cat-file -e ":$path" 2>/dev/null || return 1           # deleted from the index
    git show ":$path" >"$new.raw" || die "git show failed for :$path"
  else
    [[ -f $path ]] || return 1                                  # deleted in the work tree
    cat -- "$path" >"$new.raw" || die "cannot read $path"
  fi
  tr -d '\r' <"$old.raw" >"$old" || die "tr failed"
  tr -d '\r' <"$new.raw" >"$new" || die "tr failed"
  ob=$(region_bounds "$rule" "$old") || return 1
  nb=$(region_bounds "$rule" "$new") || return 1
  [[ -n $ob && -n $nb ]] || return 1
  read -r os oe <<<"$ob"
  read -r ns ne <<<"$nb"
  rc=0
  git diff --no-index --no-ext-diff -U0 -- "$old" "$new" >"$tmp/region-diff" || rc=$?
  [[ $rc -le 1 ]] || die "git diff --no-index failed ($rc)"
  while IFS= read -r line; do
    [[ $line =~ ^@@\ -([0-9]+)(,([0-9]+))?\ \+([0-9]+)(,([0-9]+))?\ @@ ]] || continue
    a=${BASH_REMATCH[1]}; b=${BASH_REMATCH[3]:-1}
    c=${BASH_REMATCH[4]}; d=${BASH_REMATCH[6]:-1}
    # Changed lines must lie inside the region. A pure insertion (b = 0) or
    # deletion (d = 0) only has a position "after line N" on that side; it may
    # sit on the region boundary, because the other side's lines are checked.
    if ((b > 0)); then ((a >= os && a + b - 1 <= oe)) || return 1
    else ((a >= os - 1 && a <= oe)) || return 1; fi
    if ((d > 0)); then ((c >= ns && c + d - 1 <= ne)) || return 1
    else ((c >= ns - 1 && c <= ne)) || return 1; fi
  done <"$tmp/region-diff"
  return 0
}

# ---- classify ----------------------------------------------------------------

failures=0
flagged=()
for p in ${paths[@]+"${paths[@]}"}; do
  shown=$(printf '%q' "$p")
  if matches "$p" "${banned[@]}"; then
    echo "OUT OF SCOPE (never allowed): $shown"
    failures=$((failures + 1))
    continue
  fi
  if [[ -n ${bad[$p]:-} ]]; then
    echo "OUT OF SCOPE (symlink or submodule entry): $shown"
    failures=$((failures + 1))
    continue
  fi
  if ! matches "$p" "${allowed[@]}" && ! { [[ ${#extra[@]} -gt 0 ]] && matches "$p" "${extra[@]}"; }; then
    echo "OUT OF SCOPE (not allowed for '$label'): $shown"
    failures=$((failures + 1))
    continue
  fi
  if [[ -n ${region[$p]:-} ]]; then
    ok=true
    check_region "$p" "${region[$p]}" index || ok=false
    if $ok && $worktree; then check_region "$p" "${region[$p]}" worktree || ok=false; fi
    if ! $ok; then
      echo "OUT OF SCOPE (changes outside ${region[$p]}): $shown"
      failures=$((failures + 1))
      continue
    fi
  fi
  if [[ ${#review[@]} -gt 0 ]] && matches "$p" "${review[@]}"; then flagged+=("$shown"); fi
done

echo "check_pr_scope: label '$label', base $base_oid ($base)"
if [[ -n $commits ]]; then echo "commits since base:"; echo "$commits"; fi
if [[ ${#extra[@]} -gt 0 ]]; then echo "manifest entries:"; printf '  %s\n' "${extra[@]}"; fi
if [[ ${#flagged[@]} -gt 0 ]]; then echo "hunk review required (whole-file permission):"; printf '  %s\n' "${flagged[@]}"; fi

if [[ $failures -gt 0 ]]; then
  echo "check_pr_scope: $failures of ${#paths[@]} path(s) outside '$label'" >&2
  exit 1
fi
echo "check_pr_scope: ${#paths[@]} path(s) within '$label'"
