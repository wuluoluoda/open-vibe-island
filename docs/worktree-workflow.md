# Branch Workflow

This file keeps its historical `worktree-workflow.md` name for existing links,
but the current default workflow is branch-only in the current checkout.

## Goals

- keep `main` stable enough to integrate and verify
- keep each change on a focused, reviewable branch
- reduce accidental interference across unrelated slices
- keep merge and rollback boundaries obvious
- avoid extra Git worktrees unless the user explicitly asks for them

## Roles

### 1. Local development checkout

- Path: `/Users/wuluoluo/work/code.app.org/open-vibe-island`
- Usual branch: `dev`
- Purpose: develop, run, and verify the current local Dev app

Rules:

- Use this checkout as the normal place to work.
- Create or switch to a focused topic branch in this checkout before editing.
- Do not create a new Git worktree unless the user explicitly asks for one.
- Refresh `~/Applications/Open Island Dev.app` from the current checkout and
  branch when bundle semantics, LaunchServices, or installed-hook behavior
  matter.

### 2. Topic branches

- Branch pattern: `feat/<topic>`, `fix/<topic>`, `docs/<topic>`, or
  `investigate/<topic>`
- Purpose: isolate one coherent slice in the current checkout

Rules:

- One branch should represent one coherent slice.
- Keep each branch focused on a narrow file ownership area when possible.
- If two slices would touch many of the same files, do not run them in parallel
  unless one slice clearly owns the shared files.
- If parallel work truly needs separate checkouts, create worktrees only after
  the user asks for that setup.

## Standard Lifecycle

### Start a topic branch

From the current checkout:

```bash
git status -sb
git switch -c <branch-name>
```

Example:

```bash
git status -sb
git switch -c feat/island-polish
```

If the current branch is already the right focused branch, keep using it.

## Work on the branch

Inside the current checkout:

```bash
git status -sb
```

Then follow the normal repository workflow:

1. read the relevant files
2. make one coherent change
3. verify the change
4. commit before stopping

If the branch needs new `main` changes during development:

```bash
git fetch origin
git rebase origin/main
```

If rebase is risky for that slice, merge `origin/main` into the topic branch
explicitly instead.

## Integrate back into `main`

First make sure the topic branch is committed and verified.

Push the feature branch and open a PR targeting `main`. After the PR merges,
update a clean `main` checkout if one is being used:

```bash
git switch main
git fetch origin
git pull --ff-only origin main
```

## Push policy

- Push topic branches when you want backup, review, or collaboration.
- Do not push `main` directly.
- Merge through PRs, then update any local `main` checkout with
  `git pull --ff-only`.

## Cleanup

After the topic branch is merged:

```bash
git branch -d <branch-name>
```

If the branch was pushed upstream:

```bash
git push origin --delete <branch-name>
```

Only remove a worktree if the user explicitly asked to create one for that
workstream.

## Recommended Conventions

- Keep topic names short and concrete: `codex-hooks-noise`,
  `island-geometry`, `claude-usage`.
- Do not leave long-lived unmerged branches drifting far away from
  `origin/main`.
- If a branch becomes exploratory rather than shippable, rename it into
  `investigate/<topic>` or close it.
- When assigning work to multiple agents, split by file ownership or subsystem,
  not by vague goal.

## Related Project Skill

This repository's current branch-only workflow and local Dev app verification
steps are maintained in the project skill:

- `.codex/skills/open-island-workflow/SKILL.md`

## Suggested Workstream Layout

Good parallel split:

- `feat/island-visual-polish`: `Sources/OpenIslandApp/Views/*`
- `fix/codex-hook-installer`: `Sources/OpenIslandCore/CodexHookInstaller.swift`
- `investigate/jump-accuracy`: terminal jump diagnostics and docs

Bad split:

- two branches both editing `AppModel.swift`
- one branch mixing hook installer work, island UI changes, and docs cleanup
- direct feature edits on `main`
