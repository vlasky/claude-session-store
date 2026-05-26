# Changelog

## 1.0.0 — 2026-05-26

Initial release.

- Session-scoped temp directory with automatic cleanup via SessionStart/SessionEnd hooks.
- `session-set`, `session-get`, `session-del`, `session-keys` for key-value storage.
- `session-incr`, `session-decr` for atomic counter operations (init to 0 if missing).
- `session-list` for ordered list management (add, rm, rm-all, has, count, show, clear).
- `session-list` set operations: diff, intersect, union (awk-based, order-preserving).
- Skill with proactive triggers for stateful multi-turn activities.
