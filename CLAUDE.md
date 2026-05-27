# claude-session-store

Session-scoped scratch storage for Claude Code plugins. Provides `$CLAUDE_SESSION_DIR` — a temp directory any tool can read/write, automatically cleaned up on session end.

## How it works

1. **SessionStart hook** creates `/tmp/claude-session-<SESSION_ID>` and exports `$CLAUDE_SESSION_DIR` via `CLAUDE_ENV_FILE`.
2. **SubagentStart hook** assigns each subagent a unique `$CLAUDE_AGENT_NS`, providing automatic private namespacing.
3. **During the session**, any tool can read/write files in that directory — either directly or via the `session-set`/`session-get` CLI tools.
4. **SessionEnd hook** receives the `session_id` via stdin JSON and `rm -rf`s the directory.

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

Subagents automatically get private storage via `$CLAUDE_AGENT_NS` (set by SubagentStart hook):

- **Without `--shared`** in a subagent: reads/writes go to `.ns/<agent-id>/` (private)
- **With `--shared`** in a subagent: reads/writes go to the session root (shared)
- **In the main session**: everything goes to the root (no namespace). `--shared` is a no-op.

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
- **Automatic agent namespacing** — SubagentStart hook injects `CLAUDE_AGENT_NS` (from the hook's `agent_id` field or a generated UUID). Tools route to `.ns/<id>/` when set. No manual namespace management required.
- **Shared + private model** — subagents default to private storage; `--shared` flag accesses the session root. Main session is always shared (backward-compatible).
- **Plain files in /tmp** — no database, no dependencies. Fast, portable, trivially debuggable.
- **No permissions model** — all tools in the session can access shared namespace. Private namespaces provide isolation, not security.
