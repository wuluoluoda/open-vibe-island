# Safe Tool Versioning For Open Island

Use this skill when working in this repository on branch/worktree management, local dev app version checks, build checkpoint tags, releases, or any change that must be safely tested in the running macOS app.

## Repository-Specific Rules

- Start every round with `git status -sb`.
- Read [AGENTS.md](../../../AGENTS.md) and [docs/tool-versioning.md](../../../docs/tool-versioning.md) for the current workflow.
- Do not edit directly on `main`.
- Use a focused topic branch in the current checkout for code, app, or workflow changes.
- Do not create a new git worktree unless the user explicitly asks for one.
- Treat `codex/codex-island-suite` as the current local continuous-testing branch unless the user names another branch.
- Treat `OpenIslandApp` as the canonical executable product.
- Refresh `~/Applications/Open Island Dev.app` with `zsh scripts/launch-dev-app.sh`; do not rely on opening the bundle alone.

## Orientation Commands

```bash
git status -sb
git log --oneline --decorate -5
git branch --show-current
```

## Topic Branch Base Selection

Use `origin/main` for work intended for normal integration:

```bash
git fetch --all --prune
git switch -c fix/<topic> origin/main
```

Use `codex/codex-island-suite` for fixes to the version currently being tested locally:

```bash
git switch codex/codex-island-suite
git switch -c fix/<topic>
```

State which base was used and why.

## Verification

Use the narrowest meaningful verification:

```bash
swift build --product OpenIslandApp
git diff --check
```

For local runtime verification:

```bash
zsh scripts/launch-dev-app.sh
pgrep -fl "Open Island Dev|OpenIslandApp"
ls -l "$HOME/Applications/Open Island Dev.app/Contents/MacOS/OpenIslandApp" \
      .build/arm64-apple-macosx/debug/OpenIslandApp
```

If tests are blocked by the local Swift toolchain, report the exact error and continue with the best available build/runtime verification.

## Integrating Into The Current Testing Branch

When the user says to apply, use, switch to, or merge a fix into the current app branch:

```bash
cd /Users/wuluoluo/Documents/open-vibe-island
git status -sb
git switch codex/codex-island-suite
git merge --ff-only <topic-branch>
zsh scripts/launch-dev-app.sh
```

If fast-forward is impossible, inspect and explain before rebasing or merging.

## Tag Decision

Create an annotated build checkpoint tag only after verification:

```bash
git tag -a build/<topic>-YYYYMMDD-<shortsha> \
  -m "build: <topic> checkpoint" <commit>
```

Ask before creating a release tag such as `v1.0.30`.

## Final Summary

Include:

- branch
- commit
- merge target
- verification result
- running app evidence, if refreshed
- tag name, if created
- remaining gaps
