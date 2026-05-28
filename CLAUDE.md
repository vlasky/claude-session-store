# claude-session-store

Session-scoped scratch storage for Claude Code plugins. Provides `$CLAUDE_SESSION_DIR` — a temp directory any tool can read/write, automatically cleaned up on session end.

## How it works

1. **SessionStart hook** creates `/tmp/claude-session-<SESSION_ID>` and exports `$CLAUDE_SESSION_DIR` via `CLAUDE_ENV_FILE`.
2. **SubagentStart hook** gives each subagent a private dir: creates `<root>/.ns/<agent-id>/`, exports `$CLAUDE_SESSION_ROOT` (the shared root), exports `$CLAUDE_AGENT_NS` (the agent id), and overrides `$CLAUDE_SESSION_DIR` to point at the private dir.
3. **During the session**, any tool can read/write files in that directory — either directly or via the `session-set`/`session-get` CLI tools.
4. **SessionEnd hook** receives the `session_id` via stdin JSON and `rm -rf`s the entire session directory (including all private namespaces).

## CLI tools (added to PATH)

All commands accept `--shared` to operate on the shared namespace (visible to all agents).

```
session-set [--shared] KEY VALUE          Store a value (use VALUE=- to read from stdin)
session-get [--shared] KEY                Retrieve a value (exit 1 if not found)
session-del [--shared] KEY                Delete a key
session-incr [--shared] KEY [AMOUNT]      Increment numeric key (default +1, inits to 0)
session-decr [--shared] KEY [AMOUNT]      Decrement numeric key (default -1, inits to 0)
session-keys [--shared]                   List all stored keys
session-list [--shared] KEY COMMAND ...   Manage ordered lists (add, rm, rm-all, has, count, show, clear,
                                          diff OTHER, intersect OTHER, union OTHER)
```

## Agent namespacing

Subagents automatically get private storage via the SubagentStart hook, which **repoints `$CLAUDE_SESSION_DIR` at the agent's private dir** and exports `$CLAUDE_SESSION_ROOT` for shared access:

- **Without `--shared`** in a subagent: CLI reads/writes go to `$CLAUDE_SESSION_DIR` (= `.ns/<agent-id>/`, private). Direct file access through `$CLAUDE_SESSION_DIR` lands in the same place — the CLI default and direct access agree.
- **With `--shared`** in a subagent: CLI reads/writes go to `$CLAUDE_SESSION_ROOT` (shared root, visible to all agents).
- **In the main session**: `$CLAUDE_SESSION_DIR` is the shared root and `$CLAUDE_SESSION_ROOT` is unset. `--shared` is accepted but has no effect.

The `--shared` flag must precede the key. Once a positional argument appears, option parsing stops, so values starting with `--` round-trip naturally:

```
session-set --shared mykey --some-literal-value   # value is --some-literal-value
```

If the **key itself** would start with `--`, use `--` in the leading position to terminate option parsing (POSIX convention):

```
session-set --shared -- --weird-key --some-value
```

## Plugin structure

```
.claude-plugin/plugin.json   Plugin manifest (registers hooks)
hooks/session-start          Creates session dir, exports env var
hooks/subagent-start         Assigns CLAUDE_AGENT_NS for namespace isolation
hooks/session-end            Cleans up session dir
bin/session-{set,get,del,incr,decr,keys}  CLI tools for key-value access
skills/session/SKILL.md      Teaches Claude when/how to use session storage
CLAUDE.md                    This file
```

## Updating

To force an update to the installed plugin after pushing changes:
```
claude plugin marketplace update claude-session-store
claude plugin uninstall claude-session-store
claude plugin install claude-session-store
```
Then run `/reload-plugins` inside your session to apply.

## Design decisions

- **Keyed to `CLAUDE_CODE_SESSION_ID`** — undocumented but stable env var. Fallback: the plugin could generate its own UUID, but the session ID is simpler and directly corresponds to the SessionEnd hook's stdin `session_id` field.
- **Subagent namespacing by env override, not by CLI logic** — SubagentStart points `$CLAUDE_SESSION_DIR` at the private dir and exposes the shared root as `$CLAUDE_SESSION_ROOT`. CLI tools just read one of those two vars; they never interpolate `agent_id` into a path. This means direct file access (`echo > $CLAUDE_SESSION_DIR/foo`) and `session-set foo` end up in the same namespace, eliminating the silent-bypass footgun.
- **`agent_id` is path-validated at the hook** — sanitized against `[A-Za-z0-9_-]+`; anything else triggers the UUID fallback. Closes the `..`-in-`agent_id` traversal vector.
- **Leading-only `--shared` + `--` terminator** — mid-arg `--shared` is treated as a positional, so `session-list deck add a --shared b` doesn't silently switch namespaces. To store the literal value `--shared`, just put it in value position: `session-set --shared key --shared` (parsing stops at the first positional). Use a leading `--` only when the key itself starts with `--`.
- **Plain files in /tmp** — no database, no dependencies. Fast, portable, trivially debuggable.
- **No permissions model** — all tools in the session can access the shared root. Private namespaces provide isolation, not security.
