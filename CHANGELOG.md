# Changelog

## 1.2.0 — 2026-07-05

Robustness, atomicity, work queues, and a test suite.

- **Atomic writes**: `session-set`/`session-incr`/`session-decr` now write via temp file + rename, so lock-free readers (`session-get`) can never observe an empty or partially written value. `session-list add` gets the same treatment: a multi-item batch is visible all-or-nothing.
- **`session-list KEY pop`**: atomically print and remove the first item (exit 1 when empty). The safe primitive for distributing a shared work queue across parallel subagents.
- **Hook hardening**: `CLAUDE_CODE_SESSION_ID` is now validated against `[A-Za-z0-9_-]+` at both SessionStart and SessionEnd (an empty/unsafe ID previously reached the path used by `rm -rf`); both hooks no-op gracefully when harness env vars are missing.
- **Stale-dir GC**: SessionStart sweeps this user's `claude-session-*` dirs in which nothing (contents included) has been modified for 7 days, cleaning up after crashes where SessionEnd never fired. Contents mtime is the liveness signal, so a long-running session that writes any key is never reaped; the live session's dir is also touched on every start.
- **Session dir verified on reuse**: `mkdir -p` leaves a pre-existing dir's owner/mode untouched, so SessionStart now refuses a dir it doesn't own and re-asserts mode 0700 on every start.
- **Base dir is `${TMPDIR:-/tmp}`**: on macOS this is the per-user 0700 temp dir, keeping scratch data out of world-readable /tmp.
- **Explicit PATH wiring**: SessionStart appends a self-guarding PATH entry for the plugin's `bin/` to `CLAUDE_ENV_FILE` (idempotent across repeated sourcing and repeated SessionStarts).
- **Uniform `--help`/`-h`** across all tools, exit 0, works even when the plugin env is not active. A literal `--help` key remains reachable via `session-get -- --help`.
- **Lock fix**: the flock branch of `with_lock` captured the command status in dead code under `set -e`; now explicit. `SESSION_STORE_NO_FLOCK=1` forces the perl path (for tests).
- **Test suite + CI**: `tests/run-tests.sh` (120 assertions: parsing edge cases, concurrency on both lock paths, torn-read checks, hook behaviour incl. GC and traversal attempts), run by GitHub Actions on Linux and macOS, including a macOS pass under bash 3.2, plus shellcheck.
- Docs: fixed drifted plugin-structure listing, synced marketplace version, documented `jq` requirement and temp-dir reaping caveat.

## 1.1.0 — 2026-05-28

Agent namespace isolation for parallel subagents.

- SubagentStart hook (registered in `hooks/hooks.json`) gives every subagent a private scratch dir:
  - `$CLAUDE_AGENT_NS` is set to the subagent's id.
  - `$CLAUDE_SESSION_ROOT` captures the original shared root.
  - `$CLAUDE_SESSION_DIR` is overridden to `<root>/.ns/<agent-id>/`, so direct file writes through `$CLAUDE_SESSION_DIR` are private by default.
- All CLI tools (`session-set`, `session-get`, `session-del`, `session-incr`, `session-decr`, `session-keys`, `session-list`) accept a leading `--shared` flag to operate on the shared root.
- The `--shared` flag is only consumed as a leading option; pass `--` to end option parsing so values like `--shared` round-trip correctly.
- `agent_id` from the hook input is validated against `[A-Za-z0-9_-]+`; unsafe values fall through to a generated UUID.
- Main session behavior is unchanged (no namespace, `--shared` is a no-op).
- Private namespaces are isolated — one subagent cannot read another's private keys.
- Shared counter/list operations work across agents (e.g. parallel `session-incr --shared total`).

## 1.0.0 — 2026-05-26

Initial release.

- Session-scoped temp directory with automatic cleanup via SessionStart/SessionEnd hooks.
- `session-set`, `session-get`, `session-del`, `session-keys` for key-value storage.
- `session-incr`, `session-decr` for atomic counter operations (init to 0 if missing).
- `session-list` for ordered list management (add, rm, rm-all, has, count, show, clear).
- `session-list` set operations: diff, intersect, union (awk-based, order-preserving).
- Skill with proactive triggers for stateful multi-turn activities.
