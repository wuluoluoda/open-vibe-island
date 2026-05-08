# Tool Versioning And Local Runtime Workflow

This project uses the Safe Tool Versioning workflow because Open Island is a local, continuously tested macOS tool. A change is not truly done when the code compiles; it is done when the intended branch contains the commit, the local dev app has been refreshed from that commit when needed, and the checkpoint can be identified later.

## Branch Roles

- `main`: shared integration branch. Keep it stable and update it through PR/integration only.
- `codex/codex-island-suite`: current local continuous-testing branch for the Codex island workstream. When the user asks whether the local app has a fix, this branch is the first branch to inspect unless they name another one.
- `fix/<topic>`: one bug fix.
- `feat/<topic>`: one feature.
- `docs/<topic>`: one documentation or workflow change.
- `investigate/<topic>`: one investigation that may later become a fix.

Do not edit directly on `main`. Do not edit directly in a shared worktree if a topic worktree can be created.

## Start Of Every Round

Run these before making decisions:

```bash
git status -sb
git log --oneline --decorate -5
git branch --show-current
git worktree list
```

Use the output to answer three questions:

1. Which branch is this work based on?
2. Is the working tree clean?
3. Is this change targeting `main`, the local testing branch, or a topic branch?

## Creating A Topic Worktree

For work intended for `main`, prefer `origin/main`:

```bash
git fetch --all --prune
git worktree add -b fix/<topic> ../open-vibe-island-<topic> origin/main
```

For a bug that exists in the currently running local dev app, branch from the current local testing branch:

```bash
git worktree add -b fix/<topic> ../open-vibe-island-<topic> codex/codex-island-suite
```

Say which base you chose and why. This avoids the confusion where a fix exists on an unrelated branch but the app the user is running never receives it.

## Commit Policy

Commit every completed round:

```bash
git diff --check
git add <files>
git commit -m "fix: concise behavior summary"
```

Commit when:

- a bug fix is verified
- a UI behavior is testable end to end
- a workflow or documentation update is complete
- you are about to switch tasks
- the user may need to roll back or compare versions

Keep unrelated changes in separate commits.

## Integrating Into The Local Testing Branch

When the user asks to use a fix in the current app, integrate it into `codex/codex-island-suite` unless they specify another branch.

```bash
cd /Users/wuluoluo/Documents/open-vibe-island
git status -sb
git merge --ff-only <topic-branch>
```

If fast-forward is not possible, inspect before choosing rebase or merge. Do not force it blindly.

## Refreshing The Running Dev App

For app-runtime changes, the local app must be rebuilt and relaunched from the current repo state:

```bash
zsh scripts/launch-dev-app.sh
pgrep -fl "Open Island Dev|OpenIslandApp"
ls -l "$HOME/Applications/Open Island Dev.app/Contents/MacOS/OpenIslandApp" \
      .build/arm64-apple-macosx/debug/OpenIslandApp
```

Opening the bundle without `scripts/launch-dev-app.sh` can relaunch an old binary. Always use the script when the user asks to launch, restart, or verify the dev app.

For TCC-sensitive work such as Accessibility, Automation, precision jump, or installed hooks, run this once before repeated manual verification:

```bash
zsh scripts/setup-dev-signing.sh
```

## Answering "Which Version Is Running?"

Use evidence, not memory:

```bash
git log --oneline --decorate -1
pgrep -fl "Open Island Dev|OpenIslandApp"
ls -l "$HOME/Applications/Open Island Dev.app/Contents/MacOS/OpenIslandApp"
```

The answer should include:

- branch
- commit
- process path or PID
- binary timestamp when useful

## Verification

Choose the narrowest meaningful verification:

- Swift compile: `swift build --product OpenIslandApp`
- deterministic harness: `scripts/harness.sh smoke` or `scripts/smoke-dev-app.sh`
- packaging: `zsh scripts/package-app.sh`
- dev app runtime: `zsh scripts/launch-dev-app.sh` plus process/binary checks

If `swift test` is blocked by local toolchain state, report the exact error and still run the best available build check.

## Build Checkpoint Tags

Create an annotated build tag after a checkpoint is verified and may be used for local builds, comparison, rollback, or handoff.

Format:

```text
build/<topic>-YYYYMMDD-<shortsha>
```

Example:

```bash
git tag -a build/codex-row-jump-stability-20260507-c85ef54 \
  -m "build: codex row jump stability checkpoint" c85ef54
```

Create a build tag only when:

- the working tree is clean
- the target commit is clear
- the relevant verification passed or the gap is explicitly documented
- the local dev app has been refreshed if the checkpoint is meant for local runtime testing

Do not create a build tag for unverified intermediate work.

## Release Tags

Release tags use semantic versioning:

```text
vMAJOR.MINOR.PATCH
```

Only create a release tag when the user explicitly intends a release and the release workflow in [releasing.md](./releasing.md) is complete. Do not use `v...` tags for local testing checkpoints.

## Rollback

Prefer reversible history:

```bash
git revert <bad-commit>
zsh scripts/launch-dev-app.sh
```

Use build tags as known-good anchors:

```bash
git switch -c investigate/rollback-check <build-tag>
```

Do not use destructive commands such as `git reset --hard` unless the user explicitly approves the data loss.

## Final Summary Checklist

Every final summary after code or workflow changes should mention:

- branch and commit
- whether it has been merged into `codex/codex-island-suite`, `main`, or only a topic branch
- verification command and result
- running app evidence when the app was refreshed
- tag name if a build or release tag was created
- verification gaps, if any

