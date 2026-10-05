# WiFi Lens Knowledge Boundary Policy

## Trust boundary

- The public repository contains only public-owned source, project metadata,
  documentation, and Agent assets.
- Other editions are maintained in separately controlled repositories.
- Public checks must not persist private names, source excerpts, local checkout
  paths, or implementation fingerprints.

## Allowed public knowledge

- Public product behavior and public-facing edition descriptions.
- Public interfaces and edition-neutral contracts present in this repository.
- Public Xcode targets, schemes, source ownership, and declared public package
  dependencies.

## Forbidden public knowledge

- Concrete downstream source paths, module names, target graphs, or types.
- Downstream architecture, persistence, storage, lifecycle, event routing,
  concurrency, algorithms, tests, fixtures, and roadmaps.
- Copies, summaries, paraphrases, or inferred reconstructions of internal
  documents.

When a statement mixes public product behavior with internal mechanics, retain
only the public behavior. Do not record private checkout paths in public notes,
code, documentation, issue reports, logs, or Agent assets.

## Boundary review method

Review files module by module. For each changed file, identify its repository,
owner, edition-neutral or edition-specific role, target membership, callers,
callees, composition entrypoint, and resource/test relationships. Trace each
cross-repository edge through its public contract and inspect native Xcode
source/resource phases and package dependencies.

A public repository may contain the shared public contract and its own native
project graph. It must not own downstream implementation targets or compile
concrete downstream behavior. Structural scripts assist review but cannot
replace inspection of source ownership and dependency direction.

Only a complete manual review with no unresolved `REVIEW` edges can produce a
boundary `PASS`.
