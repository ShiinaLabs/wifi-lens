# Agent Assets

This directory is the canonical source for repository-owned assets shared by
Codex, Claude Code, and OpenCode. Its contents are public/shared knowledge.

## Structure

- `skills/` contains reusable Agent Skills. Edit skills only here.
- `references/` contains routed project knowledge and cross-workflow guidance.
  Start with `references/README.md`.
- `references/project/` contains Agent-optimized technical references
  (architecture, testing, accessibility, BLE, charts, MCP, regulatory, and
  windowing). These are durable project facts organized for on-demand loading,
  not step-by-step workflows.
- Skill-specific references, scripts, and assets stay inside that skill's
  directory.

Project roadmaps, known issues, design records, and implementation plans live
in `docs/`; see `docs/README.md` for the index. Agent-oriented technical
references live here under `references/project/` so agents can load only
what a task needs.

Private implementation documentation stays in its separately access-controlled
repository. Public Agent assets must not copy, summarize, or mirror private
architecture, persistence, lifecycle, feature, or test details. For private
work, use an authorized checkout and its own root instructions.

## Platform Discovery

- Codex and OpenCode discover `.agents/skills/` directly.
- Claude Code discovers the same skills through relative symbolic links in
  `.claude/skills/`.
- `AGENTS.md` is the canonical repository instruction file. `CLAUDE.md` imports
  the adjacent `AGENTS.md` instead of duplicating it.

Do not copy shared skills into platform-specific directories or add generated
mirrors. Platform-only permissions, hooks, and local settings stay in the
platform's native directory.
