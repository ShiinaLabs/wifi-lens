# Security Policy

## Supported Versions

Security updates are provided for the latest released version of WiFi Lens.

| Version | Supported |
| ------- | --------- |
| Latest release | Yes |
| Older releases | No |

Before reporting an issue, please verify that it is reproducible with the
latest available release.

## Reporting a Vulnerability

Please do not report security vulnerabilities through public GitHub issues,
discussions, or pull requests.

The preferred reporting method is GitHub's private vulnerability reporting
feature:

1. Open the repository's **Security** page.
2. Select **Advisories**.
3. Click **Report a vulnerability**.

If private vulnerability reporting is unavailable, contact:

**contacts@shiinalabs.com**

Please use a subject such as:

```text
[Security] Brief vulnerability description
```

## What to Include

Please include as much of the following information as possible:

* A clear description of the vulnerability
* The affected WiFi Lens version
* The affected macOS version and Mac architecture
* Steps required to reproduce the issue
* The expected and actual behavior
* The potential security or privacy impact
* Relevant logs, screenshots, or proof-of-concept code
* Any suggested mitigation, if available

Do not include passwords, authentication tokens, private keys, or unnecessary
personal information.

WiFi Lens may display sensitive network information. Please redact SSIDs,
BSSIDs, IP addresses, DNS servers, proxy endpoints, and other private network
details unless they are strictly necessary to reproduce the vulnerability.

## Security Scope

Examples of security issues that should be reported privately include:

* Unauthorized access to data exposed by the local MCP server
* Bypassing an intended localhost-only network boundary
* Unexpected collection, storage, or transmission of Wi-Fi scan data
* Exposure of network identifiers, proxy configuration, or diagnostic results
* Unsafe handling of untrusted network data
* Vulnerabilities that could lead to code execution, privilege escalation,
  or unauthorized file access
* Security issues in the update or release process

The following are generally not considered security vulnerabilities:

* Normal Wi-Fi interference, congestion, or signal-strength inaccuracies
* Vulnerabilities in macOS, network hardware, access points, or third-party
  services that WiFi Lens does not control
* Feature requests and ordinary application bugs without a security impact
* Reports that only affect unsupported versions
* Publicly available information with no demonstrated security impact

If you are uncertain whether an issue is security-sensitive, report it
privately.

## Response Process

After receiving a report, the maintainer will aim to:

1. Acknowledge receipt within 7 days
2. Review the report and request additional information if necessary
3. Confirm whether the issue is accepted as a security vulnerability
4. Develop and test an appropriate fix
5. Coordinate disclosure with the reporter when appropriate

Resolution time depends on the severity and complexity of the issue. Please
allow reasonable time for investigation and remediation before publicly
disclosing vulnerability details.

## Coordinated Disclosure

Please do not publicly disclose an unpatched vulnerability without first
giving the maintainer a reasonable opportunity to investigate and release a
fix.

When appropriate, accepted vulnerabilities may be documented through a GitHub
Security Advisory after a corrected version is available.

## Safe Harbor

Security research performed in good faith, without harming users, accessing
unrelated private data, disrupting services, or violating applicable law, is
welcome.

The maintainer will not pursue action against researchers who follow this
policy and make a reasonable effort to avoid privacy violations, data loss,
and service disruption.
