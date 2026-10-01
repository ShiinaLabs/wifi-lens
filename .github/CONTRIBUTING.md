# Contributing to WiFi Lens

Thank you for your interest in contributing to WiFi Lens.

Bug reports, feature ideas, documentation improvements, localization fixes,
and focused code contributions are welcome.

## Before You Start

For bug fixes and small improvements, you may open a pull request directly.

Please open an issue or discussion before starting work on:

- Large new features
- Significant UI redesigns
- Architectural changes
- New third-party dependencies
- Changes affecting both the open-source and Pro editions

This helps avoid duplicated work and confirms that the proposed direction
fits the project.

## Reporting Bugs

A useful bug report should include:

- WiFi Lens version
- macOS version
- Mac architecture: Intel or Apple Silicon
- Clear reproduction steps
- Expected behavior
- Actual behavior
- Relevant screenshots or logs

WiFi Lens may display network-sensitive information. Before publishing
screenshots or logs, redact SSIDs, BSSIDs, IP addresses, DNS servers,
proxy endpoints, and other private network information.

## Development Setup

WiFi Lens requires macOS 14 or later.

```sh
git clone https://github.com/ShiinaLabs/wifi-lens
cd wifi-lens
```

Open the project with:

```sh
xed WiFiLens.xcodeproj
```

Build the open-source edition:

```sh
xcodebuild \
  -project WiFiLens.xcodeproj \
  -scheme "WiFi Lens" \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

## Project Scope and Architecture

This repository contains the open-source edition of WiFi Lens.

Unless a maintainer explicitly requests otherwise, public contributions
should be limited to the open-source and shared code paths.

Please follow these boundaries:

* Keep Wi-Fi-specific business logic inside WiFi Lens.
* Put reusable chart rendering and interaction behavior in ChartLens.
* Do not reference or describe private Pro implementation details in public code.
* Do not introduce Pro-only behavior into the open-source target.
* Add new source files only to the targets that should ship them.
* Avoid unrelated refactoring or formatting changes.

For more detail, see:

* `.agents/references/project/ARCHITECTURE.md`
* `.agents/references/project/TESTING.md`
* `.agents/references/project/ACCESSIBILITY.md`

## User-Facing Text and Localization

All user-facing strings must use the project's localization system.

* Use `String(localized:comment:)`.
* Use hierarchical lowercase localization keys.
* Add new entries to `Resources/Localizable.xcstrings`.
* Preserve English, German, Spanish, Japanese, and Simplified Chinese localization support.
* Do not embed user-facing English strings directly in SwiftUI views.

Documentation, code comments, commit messages, issues, and pull requests
should be written in English.

## Testing

Run the build before submitting a pull request:

```sh
xcodebuild \
  -project WiFiLens.xcodeproj \
  -scheme "WiFi Lens" \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

Run the unit tests:

```sh
xcodebuild \
  -project WiFiLens.xcodeproj \
  -scheme "WiFi Lens" \
  -configuration Debug \
  -destination 'platform=macOS' \
  -skipPackageUpdates \
  test \
  -only-testing:WiFiLensTests \
  -only-testing:WiFiLensCoreTests
```

UI tests are not required for normal pull requests unless the change
specifically requires them or a maintainer requests them.

Do not remove, skip, or weaken tests merely to make a change pass.
Tests should be deterministic and must not depend on execution order or
shared mutable global state.

If you could not run a required check, explain why in the pull request.

## Pull Requests

Keep each pull request focused on one logical change.

A pull request should include:

* A clear explanation of the problem
* A summary of the chosen solution
* Related issue links, where applicable
* Testing performed
* Screenshots for visible UI changes
* Documentation or localization updates where required

Draft pull requests are welcome for early technical discussion.

## AI-Assisted Contributions

AI-assisted development is allowed.

Contributors remain responsible for all submitted code and must:

* Read and understand the generated changes
* Verify that they follow the project architecture
* Run the relevant build and tests
* Remove unrelated or speculative generated changes
* Be able to explain the implementation during review

AI-generated code is held to the same quality, security, privacy, and
testing standards as manually written code.

## Contributor Recognition

The maintainer may offer an Apple-issued promo code for WiFi Lens Pro as a
thank-you to people whose accepted contributions have a substantial positive
impact on WiFi Lens.

Relevant contributions may include code improvements, bug fixes,
documentation, localization, testing, and validated issue investigation. The
maintainer considers each contribution on its own or together with a person's
other work, based on its impact, quality, relevance to current project needs,
and lasting usefulness. There are no fixed thresholds. Routine, trivial,
spammy, or automated contributions do not qualify on their own. The
number of submissions, stars, forks, or downloads does not establish
eligibility.

This recognition is voluntary. It is not compensation, a bounty, or an
entitlement. Submitting a contribution, or having one accepted, does not
guarantee a promo code.

Each person may receive one promo code. The maintainer sends codes privately.
Codes have no cash alternative. Apple controls their availability, expiration,
redemption, and storefront eligibility. WiFi Lens never asks for Apple ID
credentials to deliver a code.

This policy applies to contributions accepted on or after July 28, 2026. The
maintainer may also recognize earlier contributions but does not promise a
complete retrospective review.

## License

By contributing, you agree that your contributions will be licensed under
the Apache License 2.0 used by this repository.
