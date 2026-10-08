---
name: collaboration-rules
description: AI assistant collaboration rules — enforced behaviors and prohibitions
metadata:
  type: feedback
---

# AI Assistant Collaboration Rules

The following rules are **hard constraints** and must be followed in all circumstances. `AGENTS.md` is canonical; `CLAUDE.md` imports it for Claude Code. This document clarifies and reinforces those rules.

## Project Language

- **English is the primary language for repository-facing artifacts.** Repository-facing artifacts must be written in English, including source code comments, documentation, commit messages, issue descriptions, pull request content, and other text committed to the repository. Localization strings (`.xcstrings`) are the only exception — they support `en`, `de`, `es`, `ja`, and `zh-Hans`.
- **Agent–developer communication follows the developer's language preference.** Communication between agents and developers may use the developer's preferred language unless explicitly requested otherwise.

## Prohibited Actions

- **No committing (git commit)**: Unless the user explicitly says "commit" or equivalent in the current conversation turn, never run `git commit`. This includes `git commit --amend`, `git commit -m`, committing to submodules, and any other variant.

- **No pushing (git push)**: Unless the user explicitly says "push", never run `git push`. This includes `git push --force`, pushing to any remote, and any other variant.

- **No deleting files**: Never delete source files unless the user explicitly instructs you to. The same applies to renaming and moving files.

- **No modifying Git config**: Never run `git config` to modify repository configuration.

- **No destructive Git operations**: `git reset --hard`, `git clean -f`, and similar must be confirmed by the user.

- **Verify target before editing pbxproj**: Similar target build settings blocks can be easy to confuse. Check each target's `baseConfigurationReference` before modifying it. Never use `replace_all` on `project.pbxproj` — edit each occurrence individually with enough context.

## Commit Verification

Do not require a separate check-consent question before an authorized commit.
Select relevant verification from the change scope and respect the user's
instructions to run or skip checks. Reuse completed verification when it still
covers the current changes, and state what ran or was skipped. Explicit user
authorization is still required to commit and push.

## Must Follow

- **Repository instructions take priority**: `AGENTS.md`, relevant Agent references under `.agents/`, and project documentation under `docs/` are the authoritative guides for this project and must be consulted as routed by the task.

- **Enter plan mode**: Non-trivial implementation tasks must enter plan mode (EnterPlanMode) and receive approval before any code is written.

- **Production binary audit remains separate**: Keep the deterministic
  Production Pro artifact audit in the release verification chain.

- **Product verification**: When product behavior changes, use the relevant build
  and unit-test workflow if product verification is in scope. Do not run
  `WiFiLensUITests` or full scheme `xcodebuild test`
  commands that include UI test bundles unless the user explicitly asks for UI
  tests.

- **Place Markdown by responsibility**: Project roadmaps, known issues, design records, and implementation plans go under `docs/` (see `docs/README.md`). Agent-oriented technical references (architecture, testing, etc.) live under `.agents/references/project/`. Agent Skills and Agent-only workflow references go under `.agents/`. The only root exceptions are `AGENTS.md`, `CLAUDE.md`, and `README.md`.

## Behavioral Style

- **Concise responses**: Deliver results and key information directly. No need to summarize what was done after every response.
- **Don't guess**: Ask directly when a decision requires more information; don't assume.
- **Respect user intent**: If the user says "this is a half-finished refactor", that means they are aware of that state. Don't repeatedly flag it or mark it as a bug.
