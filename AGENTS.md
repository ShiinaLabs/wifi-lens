# AGENTS.md

This file provides guidance to AI coding agents (Codex, Copilot, Cursor, Windsurf, Claude Code, and others) when working in this repository.

## Documentation and Agent Assets

Project documentation lives under `docs/`; see [`docs/README.md`](docs/README.md) for the full index. Cross-agent workflows and behavior references live under `.agents/`; see `.agents/README.md` for the boundary. Never create standalone `.md` files at the repo root (except this file, `CLAUDE.md`, and `README.md`).

| Path | Purpose |
|------|---------|
| `docs/README.md` | Project documentation index |
| `docs/TODO.md` | Active product and engineering roadmap |
| `docs/ISSUES.md` | Active known issues and deferred defects |
| `.agents/references/README.md` | Task-oriented technical reference router |
| `.agents/references/collaboration-rules.md` | AI assistant behavior rules, enforced prohibitions, and must-follows |
| `Pro/AGENTS.md` | Entry point for tasks explicitly scoped to the private Pro edition |

## Agent Assets

Shared repository skills live under `.agents/skills/`. This directory is the single source for Codex and OpenCode; Claude Code uses symlinks under `.claude/skills/`.

Before acting on a repository task, read and follow `.agents/references/collaboration-rules.md`, then use `.agents/references/README.md` to load only task-relevant project knowledge. This explicit routing is required because shared references are not platform discovery entry points.

| File | Purpose |
|------|---------|
| `.agents/skills/i18n-completer/SKILL.md` | Scan `Localizable.xcstrings` for missing translations and fill them via the repository scripts while enforcing glossary terminology |
| `.agents/skills/protect-knowledge-boundary/SKILL.md` | Prevent private Pro implementation knowledge from entering public documentation and Agent assets |
| `.agents/skills/verify-build/SKILL.md` | Run the canonical WiFi Lens build and unit-test verification workflow |
| `.agents/references/README.md` | Route tasks to architecture, accessibility, BLE, chart, MCP, regulatory, testing, and windowing references |
| `.agents/references/collaboration-rules.md` | AI assistant behavior rules, enforced prohibitions, and must-follows |

## Edition Documentation Boundary

- Public repository documentation may acknowledge the Pro edition and link to
  documentation in the private `Pro/` submodule.
- Do not copy, summarize, or mirror Pro implementation details into the root
  repository or `.agents/`.
- For work explicitly scoped to Pro, follow `Pro/AGENTS.md` and read the private
  references it routes. Otherwise, do not load Pro documentation.

Use `.agents/skills/protect-knowledge-boundary/` for every documentation or
Agent-asset change that mentions Pro or crosses the root/submodule boundary.

<!-- knowledge-boundary-gate:start -->
Complete the manual module-by-module edition-boundary review described in `.agents/skills/protect-knowledge-boundary/SKILL.md` before completing knowledge-boundary changes.
Integrity manifest SHA-256: `0b810bcb1f5715d63cbcfd5f5d07107aa32eb8a8907b8fcc5ee66403c8ab70bd`
<!-- knowledge-boundary-gate:end -->

## Build & Test

```sh
# App — always use xcodebuild, never swift build / swift test
# Build configurations: Debug / Release
xcodebuild -project WiFiLens/WiFiLens.xcodeproj -scheme "WiFi Lens" -configuration Debug -destination 'platform=macOS' build
xcodebuild -project WiFiLens/WiFiLens.xcodeproj -scheme "WiFi Lens" -configuration Debug -destination 'platform=macOS' -skipPackageUpdates test -only-testing:WiFiLensTests
xed WiFiLens/WiFiLens.xcodeproj                   # open in Xcode GUI

# ChartLens library (standalone Swift Package)
cd ChartLens && swift build                        # build
cd ChartLens && swift test                         # test

# ChartLens Demo app (Xcode project)
xcodebuild -project ChartLensDemo/ChartLensDemo.xcodeproj -scheme "ChartLensDemo" -configuration Debug -destination 'platform=macOS' build
xed ChartLensDemo/ChartLensDemo.xcodeproj

# Website — redirect page to wifi-lens.shiinalabs.com (Astro + pnpm, outputs to dist/)
cd web && pnpm install --config.minimum-release-age=0
cd web && pnpm dev                           # dev server at localhost:4321
cd web && pnpm --config.minimum-release-age=0 build
cd web && pnpm preview                       # preview production build
```

The product name is `WiFi Lens.app` (with space). Unit tests use Swift Testing (`@Test`) with `TEST_HOST` — the test bundle is injected into the app process for `@testable import` symbol resolution. All test `.swift` files must be added to the WiFiLensTests target's Sources build phase (in `project.pbxproj`) for `xcodebuild test` to compile and run them. The `WiFiLensTests` scheme must reference the test bundle in both `<Testables>` and `<MacroExpansion>`.

Do not run UI test bundles (`WiFiLensUITests`, `WiFiLensProUITests`) or full scheme test commands that include UI tests unless the user explicitly asks for UI tests. Default verification is build plus `-only-testing:WiFiLensTests`.

When adding new test files, ensure they are:
1. Added as PBXFileReference in project.pbxproj
2. Added to the WiFiLensTests PBXGroup
3. Added as PBXBuildFile (assigned to WiFiLensTests target)
4. Listed in the WiFiLensTests target's Sources build phase (`files = (...)`)
5. Listed in the WiFiLensTests scheme's `<Testables>`

## Key Facts

- macOS 14+, Swift 6.0, SwiftUI + AppKit interop with CoreWLAN and CoreBluetooth
- `ScannerViewModel` is `@Observable`, passed via `@Bindable`
- Tests use Swift Testing (`@Test`, `#expect()`) with `@testable import WiFiLens`
- Localization: `String(localized: "domain.component.element", comment: "Context for translators")` → `Resources/Localizable.xcstrings` (`en`, `de`, `es`, `ja`, `zh-Hans`)
- Keys use hierarchical dot-notation (e.g., `settings.scan.interval_1s`, `overview.diagnosis.great.title`) — see `.agents/references/project/ARCHITECTURE.md` for full convention
- New strings must be manually added to `.xcstrings` with `"extractionState": "manual"` and explicit `en` localization — auto-extraction is off
- Use `String(format: String(localized: "format.key"), args...)` for parameterized strings, not string interpolation in keys

## Rules

- Never commit without explicit user instruction
- Before every commit, ask `Run the checks relevant to this commit before committing?` and follow the consent protocol in `.agents/references/collaboration-rules.md`
- Never push unless asked
- **English is the primary language for repository-facing artifacts.** Repository-facing artifacts must be written in English, including source code comments, documentation, commit messages, issue descriptions, pull request content, and other text committed to the repository. Only `.xcstrings` localization files are exceptions.
- **Agent–developer communication follows the developer's language preference.** Communication between agents and developers may use the developer's preferred language unless explicitly requested otherwise.
- **Project `.md` docs go in `docs/`** — Agent Skills and Agent-only references belong under `.agents/`; this AGENTS.md, CLAUDE.md, and README are the only root exceptions
- When creating new docs, update [`docs/README.md`](docs/README.md) and the table above if a new top-level entry point is needed
