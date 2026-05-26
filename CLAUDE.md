# claude-session-store

Session-scoped scratch storage for Claude Code plugins. Provides `$CLAUDE_SESSION_DIR` — a temp directory any tool can read/write, automatically cleaned up on session end.

## How it works

1. **SessionStart hook** creates `/tmp/claude-session-<SESSION_ID>` and exports `$CLAUDE_SESSION_DIR` via `CLAUDE_ENV_FILE`.
2. **During the session**, any tool can read/write files in that directory — either directly or via the `session-set`/`session-get` CLI tools.
3. **SessionEnd hook** receives the `session_id` via stdin JSON and `rm -rf`s the directory.

## CLI tools (added to PATH)

```
session-set KEY VALUE          Store a value (use VALUE=- to read from stdin)
session-get KEY                Retrieve a value (exit 1 if not found)
session-del KEY                Delete a key
session-incr KEY [AMOUNT]      Increment numeric key (default +1, inits to 0)
session-decr KEY [AMOUNT]      Decrement numeric key (default -1, inits to 0)
session-keys                   List all stored keys
session-list KEY COMMAND ...   Manage ordered lists (add, rm, rm-all, has, count, show, clear,
                               diff OTHER, intersect OTHER, union OTHER)
```

## Plugin structure

```
.claude-plugin/plugin.json   Plugin manifest (registers hooks)
hooks/session-start          Creates session dir, exports env var
hooks/session-end            Cleans up session dir
bin/session-{set,get,del,incr,decr,keys}  CLI tools for key-value access
skills/session/SKILL.md      Teaches Claude when/how to use session storage
CLAUDE.md                    This file
```

## Design decisions

- **Keyed to `CLAUDE_CODE_SESSION_ID`** — undocumented but stable env var. Fallback: the plugin could generate its own UUID, but the session ID is simpler and directly corresponds to the SessionEnd hook's stdin `session_id` field.
- **Flat key-value** — no nested namespaces. Plugins wanting isolation can prefix keys (e.g. `randkit-deck`, `myapp-counter`).
- **Plain files in /tmp** — no database, no dependencies. Fast, portable, trivially debuggable.
- **No permissions model** — all tools in the session share the same namespace. This is scratch storage, not a security boundary.
