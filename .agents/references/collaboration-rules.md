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

- **Verify target before editing pbxproj**: OSS and PRO target build settings blocks look nearly identical. Check `baseConfigurationReference` (`OSS.xcconfig` vs `PRO.xcconfig`) before modifying any block. Never use `replace_all` on pbxproj — edit each occurrence individually with enough context.

## Commit Check Consent

For every commit request, ask the user exactly:

> Run the checks relevant to this commit before committing?

Ask before running build, test, formatting, knowledge-boundary, integrity, or
other checks whose purpose is to gate that commit.

- If the user answers yes, select checks from the intended commit scope and
  run fresh checks before committing. Report failures instead of committing
  through them unless the user gives new direction.
- If the user answers no, the commit may proceed without pre-commit checks.
  The final report must state that checks were skipped by user choice.
- If the user has not answered, neither run pre-commit checks nor commit.
- Consent applies to one commit request only. Ask again for every later commit,
  including another commit in the same conversation.

## Must Follow

- **Repository instructions take priority**: `AGENTS.md`, relevant Agent references under `.agents/`, and project documentation under `docs/` are the authoritative guides for this project and must be consulted as routed by the task.

- **Enter plan mode**: Non-trivial implementation tasks must enter plan mode (EnterPlanMode) and receive approval before any code is written.

- **Boundary verification**: When a commit touches the OSS/Pro boundary, the
  relevant check is a manual module-by-module review of file locations, target
  membership, composition seams, and dependency direction. Build success,
  unit-test results, and repository-wide scripts cannot establish a boundary
  `PASS`.

- **Product verification**: When product behavior changes, use the relevant build
  and unit-test workflow if product verification is in scope. Do not run
  `WiFiLensUITests`, `WiFiLensProUITests`, or full scheme `xcodebuild test`
  commands that include UI test bundles unless the user explicitly asks for UI
  tests. Product verification does not replace the manual boundary review.

- **Place Markdown by responsibility**: Project roadmaps, known issues, design records, and implementation plans go under `docs/` (see `docs/README.md`). Agent-oriented technical references (architecture, testing, etc.) live under `.agents/references/project/`. Agent Skills and Agent-only workflow references go under `.agents/`. The only root exceptions are `AGENTS.md`, `CLAUDE.md`, and `README.md`.

## Behavioral Style

- **Concise responses**: Deliver results and key information directly. No need to summarize what was done after every response.
- **Don't guess**: Ask directly when a decision requires more information; don't assume.
- **Respect user intent**: If the user says "this is a half-finished refactor", that means they are aware of that state. Don't repeatedly flag it or mark it as a bug.
