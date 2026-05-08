---
name: open-island-workflow
description: Use when working on this Open Island / open-vibe-island repository, especially tasks that mention Open Island, Vibe Island, Codex island suite, local dev app testing, repo workflow, branches, commits, tags, or performance fixes. Enforces the user's current branch-only workflow and repository verification expectations.
---

# Open Island Workflow

## Overview

Follow the user's current local Open Island workflow. Create or switch to a topic branch in the current checkout; do not create a new git worktree unless the user explicitly asks for one.

## Start

1. Run `git status -sb` in the repository before edits.
2. Read `AGENTS.md`, `CLAUDE.md`, or relevant docs when the task touches workflow, release, app launch, hooks, verification, or integration expectations.
3. If not already on a focused branch, create or switch to a topic branch in the current checkout, for example `fix/performance-hotspots`.
4. If older repository docs say to create a worktree, treat that as superseded by the user's branch-only preference unless the user reaffirms worktrees for the task.

## Editing

1. Read relevant source files before editing.
2. Keep each round to one coherent change.
3. Do not overwrite user changes or use destructive git commands.
4. Use native Swift/macOS patterns already present in the repository.

## Verification

1. Run the most relevant targeted check for the changed area, commonly `swift test`, a narrower test target, `swift build`, or a project script.
2. For local app runtime changes, prefer the repo's dev app script when the user asks to test the app: `zsh scripts/launch-dev-app.sh`.
3. State any verification gap clearly.

## Finish

1. Commit every completed file-changing round on the topic branch with a conventional message.
2. Do not push, tag, or open a PR unless the user asks, or the repository workflow for the exact task explicitly requires it and the user has agreed.
3. Summarize changed files, verification, branch, and commit hash.
