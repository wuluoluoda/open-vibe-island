# Worktree Playbook

This is an optional isolation playbook, not the default repository workflow.
Use it only when the user explicitly asks for a worktree, asks for parallel
isolated checkouts, or agrees that a risky/long-running slice should be kept
outside the current checkout.

For ordinary Codex work, follow `AGENTS.md` and
`.codex/skills/open-island-workflow/SKILL.md`: work in the current checkout on
a focused topic branch, commit there, and do not merge back into `dev` or
another branch unless the user explicitly asks.

## Goals

- keep `main` and `dev` stable while isolated work is underway
- give each parallel agent or human one separate checkout when needed
- reduce accidental interference across unrelated slices
- keep merge and rollback boundaries obvious
- make cleanup predictable after the isolated branch is integrated

## Roles

### 1. Current development checkout

- Path: `/Users/wuluoluo/work/code.app.org/open-vibe-island`
- Usual branch: `dev`
- Purpose: normal development, running, and verification of the local Dev app

Rules:

- This is the default place to work.
- Do not create a worktree from here unless the user explicitly asks.
- When the user does ask for a worktree, start from a clean status in this
  checkout whenever possible.

### 2. Optional topic worktrees

- Path pattern: `/Users/wuluoluo/work/code.app.org/open-vibe-island-<topic>`
- Branch pattern: `feat/<topic>`, `fix/<topic>`, `docs/<topic>`, or
  `investigate/<topic>`
- Purpose: isolated implementation for one coherent slice

Rules:

- One worktree owns one branch.
- One branch should represent one coherent slice.
- If multiple agents are working in parallel, each gets a separate worktree and
  branch.
- If two slices would touch many of the same files, do not run them in parallel
  unless one slice clearly owns the shared files.
- Do not merge or fast-forward completed work into `dev`, `main`, or another
  local testing branch unless the user explicitly asks for that integration.

## Standard Lifecycle

### Create a topic worktree

Use this only after the user has explicitly asked for a worktree.

From the current development checkout, or any clean checkout:

```bash
git status -sb
git fetch origin
git worktree add /Users/wuluoluo/work/code.app.org/open-vibe-island-<topic> -b <branch-name> <start-point>
```

Choose `<start-point>` deliberately:

- Use `origin/main` for independent feature work intended for PR review.
- Use local `dev` only when the user asks to isolate a fix for behavior already
  visible in the current local Dev app.

Examples:

```bash
git worktree add /Users/wuluoluo/work/code.app.org/open-vibe-island-island-polish -b feat/island-polish origin/main
git worktree add /Users/wuluoluo/work/code.app.org/open-vibe-island-row-jump -b fix/row-jump dev
```

State the chosen start point before editing.

## Work inside the topic worktree

Inside the topic worktree:

```bash
git status -sb
```

Then follow the normal repository workflow:

1. read the relevant files
2. make one coherent change
3. verify the change
4. commit before stopping
5. stop on the topic branch unless the user explicitly asks you to integrate it
   into `dev`, `main`, or another branch

If the branch needs new `main` changes during development:

```bash
git fetch origin
git rebase origin/main
```

If rebase is risky for that slice, merge `origin/main` into the topic branch
explicitly instead.

## Integrate Back Into `main`

First make sure the topic branch is committed and verified.

Push the feature branch and open a PR targeting `main` when the user asks for
remote review or integration. After the PR merges, update any local `main`
checkout being used:

```bash
git switch main
git fetch origin
git pull --ff-only origin main
```

## Local Dev App Integration

Do not integrate a topic worktree back into `dev` automatically.

Only when the user explicitly asks to test or integrate that branch into the
local Dev app:

1. make sure the topic worktree is committed and verified
2. switch to the development checkout
3. merge or fast-forward the requested branch into `dev`
4. run `zsh scripts/launch-dev-app.sh`
5. confirm the running process or binary timestamp

## Push Policy

- Push topic branches when the user wants backup, review, or collaboration.
- Do not push `main` directly.
- Do not push `dev` unless the user explicitly asks.
- Merge through PRs for `main`.

## Cleanup

After the topic branch is merged and the user agrees cleanup is appropriate:

```bash
git worktree remove /Users/wuluoluo/work/code.app.org/open-vibe-island-<topic>
git branch -d <branch-name>
```

If the branch was pushed upstream:

```bash
git push origin --delete <branch-name>
```

## Recommended Conventions

- Keep topic names short and concrete: `codex-hooks-noise`,
  `island-geometry`, `claude-usage`.
- Prefer sibling directories under `/Users/wuluoluo/work/code.app.org/` so
  isolated checkouts stay easy to discover.
- Do not leave long-lived unmerged worktrees drifting far away from
  `origin/main`.
- If a worktree becomes exploratory rather than shippable, rename the branch
  into `investigate/<topic>` or close it.
- When assigning work to multiple agents, split by file ownership or subsystem,
  not by vague goal.

## Related Project Skill

This repository's default branch-only workflow and local Dev app verification
steps are maintained in the project skill:

- `.codex/skills/open-island-workflow/SKILL.md`

## Suggested Workstream Layout

Good parallel split:

- `feat/island-visual-polish`: `Sources/OpenIslandApp/Views/*`
- `fix/codex-hook-installer`: `Sources/OpenIslandCore/CodexHookInstaller.swift`
- `investigate/jump-accuracy`: terminal jump diagnostics and docs

Bad split:

- two worktrees both editing `AppModel.swift`
- one branch mixing hook installer work, island UI changes, and docs cleanup
- direct feature edits on `main`
