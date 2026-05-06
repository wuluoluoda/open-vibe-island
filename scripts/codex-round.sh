#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

usage() {
    cat <<'USAGE'
Usage:
  scripts/codex-round.sh begin <round-name>
  scripts/codex-round.sh finish -m <commit-message> [round-name]

Round control:
  begin   requires a clean worktree and creates an annotated checkpoint tag
  finish  runs build verification, stages all changes, commits, and creates an annotated delivery tag

Examples:
  scripts/codex-round.sh begin codex-shelf-redesign
  scripts/codex-round.sh finish -m "feat: require contribution proof for codex shelf" codex-shelf-redesign
USAGE
}

status_short() {
    git status -sb
}

require_clean_worktree() {
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "worktree is not clean; commit, stash, or inspect changes before starting a new round" >&2
        status_short >&2
        exit 1
    fi
}

safe_component() {
    local raw="$1"
    local safe
    safe="$(print -r -- "$raw" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's#[^a-z0-9._-]+#-#g; s#^-+##; s#-+$##')"
    if [[ -z "$safe" ]]; then
        safe="round"
    fi
    print -r -- "$safe"
}

current_branch() {
    git branch --show-current
}

timestamp() {
    date -u +"%Y%m%dT%H%M%SZ"
}

create_tag() {
    local kind="$1"
    local name="$2"
    local branch
    local tag
    branch="$(safe_component "$(current_branch)")"
    tag="checkpoint/${kind}/${branch}/$(timestamp)-$(safe_component "$name")"

    git tag -a "$tag" -m "$kind checkpoint for $name on $(current_branch)"
    echo "$tag"
}

run_builds() {
    swift build --product OpenIslandApp
    swift build --product OpenIslandHooks
    swift build --product OpenIslandSetup
}

begin_round() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        usage >&2
        exit 2
    fi

    status_short
    require_clean_worktree

    local tag
    tag="$(create_tag "begin" "$name")"
    echo "created begin checkpoint tag: $tag"
}

finish_round() {
    local message=""
    local name="delivery"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -m|--message)
                shift
                message="${1:-}"
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                name="$1"
                ;;
        esac
        shift || true
    done

    if [[ -z "$message" ]]; then
        echo "finish requires -m <commit-message>" >&2
        usage >&2
        exit 2
    fi

    status_short
    run_builds

    if [[ -z "$(git status --porcelain)" ]]; then
        echo "no changes to commit"
        exit 0
    fi

    git add -A
    git commit -m "$message"

    local tag
    tag="$(create_tag "finish" "$name")"
    echo "created finish checkpoint tag: $tag"
}

command="${1:-}"
case "$command" in
    begin)
        shift
        begin_round "$@"
        ;;
    finish)
        shift
        finish_round "$@"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
