# Changelog

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
