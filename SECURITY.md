# Security Policy

## Reporting a Vulnerability

If you believe you have found a security vulnerability in HTTP-Tiny, please
report it responsibly. **Do not report security vulnerabilities through public
GitHub issues.**

### Preferred Method: GitHub Private Vulnerability Reporting

Use GitHub's [private vulnerability reporting](https://github.com/Perl-Toolchain-Gang/HTTP-Tiny/security/advisories/new)
feature to submit a report. This allows maintainers to work on a fix privately
before public disclosure.

### Alternative: Email

If you prefer email, send details to one of the maintainers:

- Christian Hansen: `chansen@cpan.org`
- David Golden: `dagolden@cpan.org`

Please encrypt sensitive reports using the maintainers' public PGP keys if
available.

### What to Include

A useful report includes:

- A description of the vulnerability and its potential impact
- Steps to reproduce the issue (proof-of-concept code is helpful)
- The affected version(s)
- Any known mitigations or workarounds

## Response Timeline

We will acknowledge receipt of your report within **7 days** and aim to provide
a fix or mitigation plan within **30 days**, depending on complexity. We will
keep you informed of our progress.

## Disclosure Policy

We follow [coordinated disclosure](https://en.wikipedia.org/wiki/Coordinated_vulnerability_disclosure).
We ask that you give us reasonable time to address the vulnerability before any
public disclosure.

## Scope

HTTP-Tiny is a minimal HTTP client. Security concerns relevant to this module
include, but are not limited to:

- TLS/SSL certificate validation bypasses
- HTTP request smuggling or response splitting
- Proxy handling issues
- Redirect handling that could expose credentials or cause SSRF

## Supported Versions

We support the latest stable release. Security fixes are applied to the current
release only; we do not backport to older versions.
