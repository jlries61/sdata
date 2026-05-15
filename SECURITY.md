# Security Policy

## Reporting a Vulnerability

Please report security vulnerabilities by email to **john@theyarnbard.com**.

Do not open a public GitHub issue for security-sensitive reports. Include a
description of the issue, steps to reproduce it, and the version of SData
affected. You can expect an acknowledgement within a few days.

## Threat Model

SData's threat model is documented in `doc/threat_model.md` and installed
alongside the binary in every package. It covers the trust model, attack
surface, STRIDE analysis, and known limitations — in particular the
`SYSTEM`/`SHELL` execution path and its mitigations.
