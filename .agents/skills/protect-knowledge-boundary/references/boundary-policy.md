# WiFi Lens Knowledge Boundary Policy

## Trust boundary

- The root repository, including `.agents/`, is public.
- `Pro/` is a private submodule and separate Git repository.
- Public checks must not persist private names, excerpts, or fingerprints.

## Allowed public knowledge

- The Pro edition and private repository exist.
- `Pro/AGENTS.md` is the instruction entrypoint for explicitly Pro-scoped work.
- A `Pro/docs/*.md` path exists and may be indexed without a content summary.
- Public interfaces and edition-neutral contracts already implemented in the
  public repository may be documented from their public source.

## Forbidden public knowledge

- Private source paths, symbol names, module structure, or concrete types.
- Private architecture, persistence, schema, storage, queues, or algorithms.
- Private state ownership, lifecycle, event routing, or concurrency behavior.
- Paid workflow implementation, private tests, fixtures, plans, or roadmap.
- Copies, summaries, paraphrases, or inferred reconstructions of private docs.

Feature existence and public product copy are not implementation knowledge.
When a statement mixes public product behavior with private mechanics, retain
only the public behavior or move the statement into `Pro/`.

## Review rule

An allowed path is an index, not permission to read and summarize its target.
For non-Pro tasks, do not load private documents into Agent context. For
explicitly Pro-scoped tasks, follow `Pro/AGENTS.md` and keep resulting private
knowledge inside the private repository.

## Boundary review method

The boundary is semantic and architectural. A review must be performed module
by module, not reduced to a repository-wide text search or a build result.
For every changed file, identify its physical repository, module ownership,
edition, target membership, callers, callees, and composition entrypoint.
Then inspect the dependency direction and the Xcode source/resource phases
that deliver it to each target.

The public repository may contain edition-neutral contracts, OSS
implementations, and Xcode wiring needed to build the separate Pro target.
Those facts alone do not disclose private implementation. The boundary fails
when public source or public target membership receives private behavior, when
the dependency direction bypasses the composition seam, or when public assets
describe private implementation knowledge.

Automated scripts may assist with navigation or protect the review
instructions, but they cannot establish that a module relationship is safe.
Only a complete manual review with no unresolved `REVIEW` edges can produce a
boundary `PASS`.
