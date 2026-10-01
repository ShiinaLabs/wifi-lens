---
name: protect-knowledge-boundary
description: Invoke only when the user explicitly requests a WiFi Lens knowledge-boundary audit or the active task names that audit as a required deliverable. This skill is opt-in only; do not run it automatically for documentation, Agent assets, Pro changes, commits, pushes, refactors, or reviews.
---

# Protect Knowledge Boundary

## Default invocation policy

**OPT-IN ONLY.** Do not run this skill automatically. Run it only when the
user explicitly requests a knowledge-boundary audit or the active task names
that audit as a required deliverable.

Do not infer permission to run it from a change touching `WiFiLensCore`, the
private Pro repository, edition composition, documentation, Agent assets, or
the OSS/Pro boundary. Do not run it before commits or pushes, after ordinary
code changes, during routine refactors, or during routine code review.

The Production Pro binary audit is a separate release invariant. Keep it in
the release verification chain; this opt-in policy does not disable it.

Keep private Pro implementation knowledge inside the `WiFiLensPro/` submodule while
allowing the public repository to index approved private entrypoints.

## Required context

Read [references/boundary-policy.md](references/boundary-policy.md) completely
before reviewing or changing knowledge-boundary content. Do not load private
Pro documentation or implementation into Agent context unless the task is
explicitly Pro-scoped. The boundary decision must come from a manual review
of modules, file locations, target membership, and dependency direction.

## Workflow

When an explicitly requested audit is part of a task, follow the per-commit
consent protocol in `.agents/references/collaboration-rules.md` before running
checks whose purpose is to gate that commit.

1. Treat the root repository as public and `WiFiLensPro/` as a separate private
   repository. Inspect their Git status and diffs separately.
2. Split the change into modules and review every changed file individually.
   For each file, record its physical location, owning module, edition
   (`OSS`, `shared contract`, or `Pro`), target membership, and role in the
   dependency graph.
3. Trace the relationships around each changed module in both directions:
   identify its callers, callees, imported contracts, composition entrypoint,
   resources, and tests. Confirm that the public side depends only on public
   or edition-neutral contracts, while private behavior remains behind the
   target-selected composition boundary.
4. Inspect Xcode project wiring manually. Review the relevant source groups,
   `PBXSourcesBuildPhase` entries, `OSS.xcconfig` / `PRO.xcconfig`, resources,
   schemes, and test target membership. A private path appearing in Pro build
   wiring is not itself a leak; the question is which target receives the
   file and whether public source imports a private implementation.
5. For every boundary-crossing edge, write a short `PASS`, `REVIEW`, or
   `FAIL` decision with the reason. An ambiguous module relationship is
   `REVIEW` and must not be silently inferred as safe.
6. Report root and Pro results separately. Do not claim completion while any
   changed module, target-membership edge, or dependency relationship remains
   unreviewed.

## Review map

Use the public repository's existing architecture map as the starting point:

- `WiFiLensCore/Sources/WiFiLensCore/` contains shared product implementation
  modules.
- `WiFiLens/Sources/WiFiLens/App/EditionCompositionContext.swift` is the
  edition-neutral context passed across the composition seam.
- `WiFiLens/Sources/WiFiLens/App/OSSEditionComposition.swift` is the public
  composition implementation and must remain safe for the OSS target.
- `WiFiLens/Configs/OSS.xcconfig` and `WiFiLens/Configs/PRO.xcconfig` select
  the target-specific compilation entrypoints.
- `WiFiLens.xcodeproj/project.pbxproj` is the source of truth for
  target membership and for the public project's Pro build wiring.

For each changed module, follow its edges through the scanner/runtime,
observation models and pipeline, presentation layer, and finally the
edition-composition seam. Do not infer a private module's internal design from
its filename, public references, or build success.

## Review record

Keep a compact record for each review. The record must be based on inspected
files and project wiring, not on a scanner summary:

| File | Physical repository | Module | Edition | Target membership | Callers / callees / composition seam | Decision |
| --- | --- | --- | --- | --- | --- | --- |
| `path` | root or `WiFiLensPro/` | concrete module | `OSS`, shared contract, or `Pro` | OSS / Pro / both / tests | inspected relationship and evidence | `PASS`, `REVIEW`, or `FAIL` |

Also list every edge that crosses an edition boundary and state why the edge is
allowed, unresolved, or forbidden. A review is incomplete if a row or edge is
omitted merely because the file did not fail an automated check.

## Decision rules

- `PASS`: every changed module and boundary edge has been manually reviewed;
  the file location, target membership, and dependency direction are clear.
- `REVIEW`: a module's ownership, target membership, or relationship is
  ambiguous. Stop and ask the user; do not infer permission to expose more
  context.
- `FAIL`: the review shows a public target receiving private implementation,
  public source importing a private concrete implementation, or private
  implementation knowledge being added to public assets.

Scripts in this directory are auxiliary lint or asset-integrity tools. Their
output cannot establish a boundary `PASS` and must never replace the manual
module-by-module review above.

Never fix a failure by weakening a rule, excluding a new path, updating hashes,
or rewriting the instruction anchor as part of an ordinary check. Changes to
protected assets require explicit user approval and a focused review. Generate
new hashes only after that review, then run all Skill tests and both checks.

## Integrity limits

Local hashes make tampering visible during normal work; they cannot stop a
committer who deliberately changes every local anchor. Trusted CI plus
CODEOWNERS approval is required for merge-level enforcement.
