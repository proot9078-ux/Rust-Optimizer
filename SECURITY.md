# Security policy

## Supported versions

| Version | Supported |
|---|---|
| 4.x | ✅ |
| 3.x and older | ❌ |

## Reporting a vulnerability

Please do **not** publish working exploit details in a public issue. Open a private
security advisory on GitHub:

<https://github.com/proot9078-ux/Rust-Optimizer/security/advisories/new>

Include:

1. affected version and Windows build;
2. whether the app was running as administrator;
3. exact steps to reproduce;
4. relevant lines from `%ProgramData%\RustOptimizer\rust-optimizer.log`;
5. impact: privilege escalation, unsafe file deletion, command injection, etc.

You should receive a response within 7 days. Please give the maintainer time to
ship a fix before public disclosure.

## Scope

This project intentionally performs administrative changes to Windows when the
user confirms them: registry writes, service changes, cache cleanup, SFC/DISM,
network reset and similar operations. Those are product features, not
vulnerabilities.

Security-relevant issues include:

- command injection through paths, environment variables or log content;
- unsafe deletion outside the documented cleanup targets;
- following reparse points / junctions into unrelated data;
- writing executable files into privileged locations without integrity checks;
- leaking secrets from logs or reports;
- bypassing the confirmation for destructive actions.

## Design rules

- No bundled third-party binaries, obfuscation or hidden downloads.
- RUST `exe`/`dll` files are never modified; nothing is injected into the game.
- Cleanup helpers skip reparse points and only remove documented cache/log files.
- Destructive cleanup modules are disabled by default and require confirmation.
- A restore point is created before the main optimization run.
- Logs stay local in `%ProgramData%\RustOptimizer`.
