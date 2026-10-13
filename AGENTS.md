# Repository guidance

This directory is its own Git repository. The parent Gnorium workspace is not a repository; run Git commands here and inspect sibling repositories separately.

- Preserve unrelated working changes. When renaming an internal API, update callers in sibling packages rather than leave obsolete aliases.
- Run focused checks for the changed behavior. Do not run full server/browser suites unless requested.
- Keep build caches and `.build` directories. Diagnose build/toolchain errors before rebuilding; do not wipe caches to troubleshoot.
- Batch related changes before building. Deployment requires an explicit user request; a local build or server restart is not deployment.
- If committing authorized work, omit attribution trailers and push normally after the commit; never force-push.

## Browser tests

Use focused suites for the changed behavior, in headless Chrome. Do not run a full parallel browser suite unless requested. Build the current client/styles before testing hydration; use local fixture servers where a database is unnecessary.

Use throwaway test accounts and scratch rows; never attribute test contributions to real users. Audit logs remain immutable. Follow TestAdmin's cleanup rules for accounts that have contributed or been logged.

When controls/classes are renamed, update selectors and fixtures as well. Check state/scroll stability and exact copied source, not just that an element exists.
