---
name: open-island-tag-checkpoint
description: Use when working in the Open Island repository and the user asks whether to create, audit, or apply Git tags, build checkpoint tags, release/version tags, tag policy, or tag cleanup. Enforces the project rule that feature branches and dev normally do not get tags; annotated build tags are considered only after integration into main when the change since the previous tag is a feature increment, important architecture/energy change, or intended distribution build; release tags require explicit user confirmation.
---

# Open Island Tag Checkpoint

## Policy

Use this skill for Open Island tag decisions. Treat tags as named integration points, not as routine development markers.

- Feature branches: do not tag. Commit only.
- `dev`: do not tag by default. Use commit hashes in summaries.
- `main`: after an integration is complete and verified, consider an annotated `build/...` tag only when the changes since the previous relevant tag are a feature increment, important architecture or energy change, or intended distribution build.
- Release/version tags such as `v1.0.31`: only on `main`, and only after asking the user for explicit confirmation.
- Emergency debugging or temporary local builds: tag only when the user explicitly asks for a temporary tag.

## Workflow

1. Start with `git status -sb`.
2. Determine the current branch with `git branch --show-current`.
3. Inspect existing tags on the current commit:
   `git tag --points-at HEAD`.
4. Find the previous relevant tag reachable from the branch:
   `git describe --tags --abbrev=0 --match 'build/*' --match 'v*' HEAD^`.
5. Review the delta:
   `git log --oneline --decorate <tag>..HEAD`
   and `git diff --stat <tag>..HEAD`.
6. Classify the delta as one of:
   - `feature milestone`: user-visible capability or workflow expansion.
   - `architecture/energy milestone`: broad runtime, performance, energy, app lifecycle, or integration behavior change.
   - `distribution build`: a point intended for a DMG, app bundle, release candidate, or shared build.
   - `ordinary fix`: bug fix, cleanup, config migration, copy tweak, or small stability patch.
7. Recommend no tag for `ordinary fix` unless the user explicitly asks.
8. If the branch is not `main`, recommend deferring any normal build/release tag until after main integration.

## Creating A Build Tag

Create only annotated build tags:

```bash
git tag -a "build/<topic>-YYYYMMDD-<shortsha>" -m "Build checkpoint for <topic>" <commit>
```

Use a concise lowercase topic, for example:

- `build/energy-modules-20260510-7e8e3a5`
- `build/codex-app-session-resync-20260511-6342792`

Before creating the tag, confirm:

- The target commit is the exact verified `main` commit unless the user explicitly requested a temporary local tag.
- The commit does not already have an appropriate `build/...` or `v...` tag.
- The tag name contains the commit date and short SHA.

## Release Tags

Never create a release/version tag silently. If the user asks for a release tag, state the exact target commit and ask for confirmation before creating it.

Use `vX.Y.Z` only for product versions intended to identify a precise release. Do not use version tags for local dev checkpoints.

## Final Summary

When a tag is created, report:

- tag name
- target commit
- whether it is a build checkpoint or release/version tag
- verification performed

When no tag is created, briefly say why, using the policy category above.
