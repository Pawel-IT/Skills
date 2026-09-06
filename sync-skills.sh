#!/usr/bin/env bash
# Keeps the skills a repo takes from this Skills repo current.
#
# A repo declares what it wants in .claude/shared-skills.txt, one skill name per
# line. This script copies those skills in. It copies rather than symlinks,
# because a project commits its skills and every clone must get real files.
#
#   sync-skills.sh <repo>            copy each named skill in, and report
#   sync-skills.sh --check <repo>    report only; exit 1 when anything differs
#   sync-skills.sh --force <repo>    overwrite a copy the repo edited locally
#   sync-skills.sh --global <name>…  symlink named skills into ~/.claude/skills
#
# A local edit stops the sync. This repo cannot tell an improvement from a stale
# copy, so it reports the difference and leaves both alone. Push the better text
# here first, then sync.

set -euo pipefail

readonly SKILLS_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MANIFEST_PATH=".claude/shared-skills.txt"
readonly GLOBAL_SKILLS_DIR="$HOME/.claude/skills"

usage() { sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

die() { printf 'sync-skills: %s\n' "$1" >&2; exit 2; }

source_of() {
  local skill="$1"
  [ -f "$SKILLS_REPO/$skill/SKILL.md" ] || die "no skill named '$skill' in $SKILLS_REPO"
  printf '%s\n' "$SKILLS_REPO/$skill"
}

read_manifest() {
  local repo="$1" manifest="$repo/$MANIFEST_PATH"
  [ -f "$manifest" ] || die "no $MANIFEST_PATH in $repo — list the skills it takes, one per line"
  sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$manifest" | grep -v '^$' || true
}

# Every version of a skill this repo ever held, as blob hashes.
published_versions() {
  local path="$1" commit
  git -C "$SKILLS_REPO" log --format=%H -- "$path" | while read -r commit; do
    git -C "$SKILLS_REPO" rev-parse --quiet --verify "$commit:$path" || true
  done
}

# ok | absent | stale | edited — one word per skill, so the caller can act on it.
#
# A copy that differs is behind us or ahead of us, and the answer decides whether
# the sync may overwrite it. Our history settles it: a copy holding text we once
# published is behind, and any other text is an edit we did not write.
state_of() {
  local skill="$1" source="$2" target="$3"
  [ -d "$target" ] || { echo absent; return; }
  diff -rq "$source" "$target" >/dev/null 2>&1 && { echo ok; return; }

  # The SKILL.md already matches, so every remaining difference is a file the
  # project changed — a reference page, a script.
  cmp -s "$source/SKILL.md" "$target/SKILL.md" && { echo edited; return; }

  local copied_version
  copied_version="$(git hash-object "$target/SKILL.md" 2>/dev/null)" || { echo edited; return; }
  if published_versions "$skill/SKILL.md" | grep -qx "$copied_version"; then
    echo stale
  else
    echo edited
  fi
}

copy_in() {
  local source="$1" target="$2"
  mkdir -p "$(dirname "$target")"
  rm -rf "$target"
  cp -R "$source" "$target"
}

sync_repo() {
  local repo="$1" mode="$2" drift=0 skill source target state wanted
  [ -d "$repo" ] || die "no directory at $repo"

  # Read the manifest before the loop. A failure inside a process substitution
  # cannot stop this function, and a silent no-op reads as a clean sync.
  wanted="$(read_manifest "$repo")" || exit 2
  [ -n "$wanted" ] || { printf '  %s names no skills\n' "$MANIFEST_PATH"; return 0; }

  while read -r skill; do
    source="$(source_of "$skill")"
    target="$repo/.claude/skills/$skill"
    state="$(state_of "$skill" "$source" "$target")"

    case "$state:$mode" in
      ok:*)          printf '  ok       %s\n' "$skill" ;;
      absent:check)  printf '  missing  %s\n' "$skill"; drift=1 ;;
      absent:*)      copy_in "$source" "$target"; printf '  added    %s\n' "$skill" ;;
      stale:check)   printf '  stale    %s — this repo has newer text\n' "$skill"; drift=1 ;;
      stale:*)       copy_in "$source" "$target"; printf '  updated  %s\n' "$skill" ;;
      edited:force)  copy_in "$source" "$target"; printf '  forced   %s — local edits overwritten\n' "$skill" ;;
      edited:*)      printf '  differs  %s — the copy in %s was edited\n' "$skill" "$repo"
                     printf '           diff -ru %s %s\n' "$source" "$target"
                     printf '           Push the better text to %s, then sync.\n' "$SKILLS_REPO"
                     drift=1 ;;
    esac
  done <<< "$wanted"

  # Anything this run would not touch is drift the caller must still settle.
  return "$drift"
}

link_global() {
  local skill source target
  mkdir -p "$GLOBAL_SKILLS_DIR"
  for skill in "$@"; do
    source="$(source_of "$skill")"
    target="$GLOBAL_SKILLS_DIR/$skill"
    if [ -e "$target" ] && [ ! -L "$target" ]; then
      die "$target is a real directory — move it aside before you link"
    fi
    ln -sfn "$source" "$target"
    printf '  linked   %s -> %s\n' "$skill" "$source"
  done
}

main() {
  case "${1:-}" in
    -h|--help|"") usage; exit 0 ;;
    --global)     shift; [ $# -gt 0 ] || die "name a skill to link"; link_global "$@" ;;
    --check)      shift; [ $# -eq 1 ] || die "name one repo"; sync_repo "$1" check ;;
    --force)      shift; [ $# -eq 1 ] || die "name one repo"; sync_repo "$1" force ;;
    -*)           die "unknown option: $1" ;;
    *)            [ $# -eq 1 ] || die "name one repo"; sync_repo "$1" sync ;;
  esac
}

main "$@"
