---
name: protect-knowledge-boundary
description: Invoke only when the user explicitly requests a WiFi Lens knowledge-boundary audit or the active task names that audit as a required deliverable. This skill is opt-in only; do not run it automatically for documentation, Agent assets, refactors, commits, pushes, or routine reviews.
---

# Protect Knowledge Boundary

## Invocation policy

**OPT-IN ONLY.** Run this skill only when the user explicitly requests a
boundary audit or the active task names it as a required deliverable.

Do not infer permission from work touching shared code, edition composition,
documentation, Agent assets, or a repository ownership change. A production
artifact check is separate from this manual source and knowledge review.

Keep implementation knowledge in the repository that owns it. Public assets
must not expose concrete downstream source paths, module names, target graphs,
algorithms, persistence details, tests, or internal plans.

## Required context

Read [references/boundary-policy.md](references/boundary-policy.md) completely
before reviewing or changing boundary content. Load a separately maintained
repository only when the task is explicitly scoped to it and the user has
provided or authorized that checkout.

## Workflow

1. Treat the public repository and each separately checked-out repository as
   distinct ownership domains. Inspect Git status and diffs independently.
2. Review every changed file. Record its repository, module, edition-neutral or
   edition-specific role, target membership, and callers/callees.
3. Trace cross-repository edges through public contracts and composition
   entrypoints. Confirm that public code depends only on public APIs and does
   not import or compile concrete downstream implementation.
4. Inspect native project references, source/resource phases, schemes, and
   package ownership. Builds and scripts cannot replace this review.
5. Mark every boundary edge `PASS`, `REVIEW`, or `FAIL`, with the inspected
   evidence. An ambiguous edge remains `REVIEW`.
6. Report public and separately checked-out repository results separately. Do
   not claim completion while any changed module, target edge, or dependency
   relationship remains unreviewed.

## Public review map

Use the public repository's architecture reference as the starting point:

- `WiFiLensCore/Sources/WiFiLensCore/` contains shared public product modules.
- `WiFiLens/Sources/WiFiLens/` contains the public app shell and its
  edition-neutral composition adapter.
- `WiFiLensCore/App/WiFiLensEditionConfiguration.swift` defines the shared
  composition contract.
- `WiFiLens.xcodeproj/project.pbxproj` owns public target membership and
  dependencies.

Follow changed modules through their callers, public contracts, composition
entrypoints, resources, and tests. Do not infer another repository's internals
from its public APIs, build success, or product description.

## Review record

| File | Repository | Module | Role | Target membership | Callers / callees / composition edge | Decision |
|---|---|---|---|---|---|---|
| `path` | public or authorized separate checkout | inspected module | public or edition-specific | inspected targets | evidence from source and project wiring | `PASS`, `REVIEW`, or `FAIL` |

List every edge crossing repository ownership and explain whether its public
contract and direction are allowed. A review is incomplete if a changed file
or dependency edge is omitted.

## Decision rules

- `PASS`: file ownership, target membership, callers, and dependency direction
  are clear and allowed.
- `REVIEW`: ownership, membership, or relationship is ambiguous. Stop and ask
  the user rather than inferring permission to expose more context.
- `FAIL`: public target membership receives downstream implementation, public
  code imports a downstream concrete type, or public assets disclose internal
  implementation knowledge.

Automated scripts are navigation and structure checks only. They cannot
establish a manual boundary `PASS`.
