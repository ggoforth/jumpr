# Security

Jumpr holds the macOS Accessibility permission and installs its own updates, so a security problem in it matters.

## Reporting a vulnerability

Please do not open a public issue for a security problem.

Report it privately through GitHub: [Report a vulnerability](https://github.com/ggoforth/jumpr/security/advisories/new) (the "Report a vulnerability" button on the repository's Security tab). Only the maintainer can see the report.

It helps to include:

- The Jumpr version (the first line of its menu bar menu) and your macOS version
- What happens, and what you expected
- Steps to reproduce it

Jumpr is maintained by one person. Reports are read, and fixes ship as an update, but there is no promised response time. Say so in the report if you would like credit when the fix is released.

## Supported versions

Only the latest release gets fixes. Jumpr offers updates on its own; you can also choose Check for Updates… from its menu bar icon.

## How updates are protected

- Every release is signed with a Developer ID certificate and notarized by Apple.
- Every update is also signed with a separate key, and Jumpr installs only updates that carry that signature.
- The update feed and the downloads are served over HTTPS.
