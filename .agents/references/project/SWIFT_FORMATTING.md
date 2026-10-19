# Swift Formatting

WiFi Lens uses the `swift-format` shipped with Xcode
(`xcrun swift-format`). The repository-root `.swift-format` is the single
source of formatting configuration for this repository.

## Configuration

- Location: `.swift-format` at the repository root.
- Base: the configuration emitted by the local Xcode toolchain
  (`xcrun swift-format dump-configuration`), with two deliberate overrides:
  - `indentation.spaces: 4` — matches the established source style.
  - `lineLength: 120` — the existing code allows longer localized calls and
    assertions.
- Every other key keeps the toolchain default. Do not add overrides without a
  repository-wide reason.
- Other editions of WiFi Lens consume this file as their formatting
  configuration source. Do not fork or duplicate it.

## Commands

Format every tracked Swift file:

```sh
git ls-files -z -- '*.swift' | xargs -0 xcrun swift-format format --in-place --parallel
```

Report findings without modifying files:

```sh
git ls-files -z -- '*.swift' | xargs -0 xcrun swift-format lint --parallel
```

Confirm which configuration applies from the current directory:

```sh
xcrun swift-format dump-configuration --effective
```

## Notes

- Keep formatting changes separate from behavior changes; they belong in their
  own commit.
- `swift-format lint` reports rule findings that `format` does not rewrite
  (for example `ReplaceForEachWithForLoop`, `UseSynthesizedInitializer`, and
  `AlwaysUseLowerCamelCase`). Fix them deliberately instead of folding them
  into a formatting-only change.
- A nested `.swift-format` in a subdirectory silently overrides the root
  configuration for that subtree.
- When configuration discovery fails, `swift-format` falls back to its
  built-in defaults without an error. `dump-configuration --effective` is the
  only way to confirm the configuration actually in use.
