# Changelog

## 1.1.0 — 2026-05-27

Agent namespace isolation for parallel subagents.

- SubagentStart hook automatically assigns `$CLAUDE_AGENT_NS` to each subagent (from hook `agent_id` or generated UUID).
- All CLI tools (`session-set`, `session-get`, `session-del`, `session-incr`, `session-decr`, `session-keys`, `session-list`) now support `--shared` flag.
- Without `--shared` in a subagent: operations go to private namespace (`.ns/<agent-id>/`).
- With `--shared`: operations go to session root (visible to all agents).
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
