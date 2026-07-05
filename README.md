# claude-session-store

Session-scoped scratch storage for [Claude Code](https://claude.ai/code).

Provides `$CLAUDE_SESSION_DIR` — a temp directory any tool can read/write, automatically cleaned up when the session ends.

## Install

```
claude plugin marketplace add vlasky/claude-session-store
claude plugin install claude-session-store
```

Or test locally:
```
claude --plugin-dir /path/to/claude-session-store
```

## Usage

### Key-Value

```bash
session-set mykey "some value"
session-get mykey              # → some value
session-del mykey
session-incr counter           # → 1 (init 0, then +1)
session-incr counter 10        # → 11
session-decr counter           # → 10
session-keys                   # list all keys
```

### Lists

```bash
session-list deck add A♠ 2♠ 3♠ 4♠ 5♠
session-list deck rm A♠ 3♠
session-list deck show         # → 2♠ 4♠ 5♠
session-list deck count        # → 3
session-list deck has 4♠       # → exit 0
session-list deck clear
```

### Work queues

`pop` prints and removes the first item atomically (under the key's lock), so
parallel consumers never receive the same item. It exits 1 when the list is
empty, which terminates a `while` loop cleanly:

```bash
session-list --shared queue add task-1 task-2 task-3

# In each parallel worker:
while item=$(session-list --shared queue pop); do
  process "$item"
done
```

### Set Operations

```bash
session-list all add a b c d e
session-list done add c d

session-list all diff done       # → a b e (in all, not in done)
session-list all intersect done  # → c d (in both)
session-list all union done      # → a b c d e (combined, deduplicated)
```

### Direct file access

```bash
echo "anything" > "$CLAUDE_SESSION_DIR/myfile"
cat "$CLAUDE_SESSION_DIR/myfile"
```

### Subagent isolation

When code runs inside a Claude Code subagent, the plugin automatically gives
that subagent a private scratch dir. Use `--shared` (before the key) to opt
into the shared root.

```bash
# In the main session:
session-set --shared config '{"iterations": 100}'

# In a subagent (env set automatically):
session-get --shared config                   # reads the parent's config
session-incr progress                          # private counter
session-set --shared "result-$CLAUDE_AGENT_NS" "42.5"  # publish to shared

echo "private write"  > "$CLAUDE_SESSION_DIR/note"     # private file
echo "shared write"   > "$CLAUDE_SESSION_ROOT/note"    # shared file
```

Environment variables in a subagent:

- `$CLAUDE_SESSION_DIR` — your private dir (`<root>/.ns/<agent-id>/`)
- `$CLAUDE_SESSION_ROOT` — the shared session root
- `$CLAUDE_AGENT_NS` — your agent id

In the main session, `$CLAUDE_SESSION_DIR` is the shared root and the other
two are unset; `--shared` is accepted but has no effect.

## How it works

1. **SessionStart** hook creates `${TMPDIR:-/tmp}/claude-session-<SESSION_ID>` (mode 0700, re-asserted on every start), exports `$CLAUDE_SESSION_DIR` via `CLAUDE_ENV_FILE`, and puts the plugin's `bin/` on `PATH`. It also sweeps this user's session dirs in which nothing has been modified for 7 days, so dirs orphaned by a crash (where SessionEnd never fired) don't accumulate; a long-running session that writes any key stays safe.
2. **SubagentStart** hook (when a subagent is spawned) creates a per-agent private dir at `<root>/.ns/<agent-id>/`, then exports `$CLAUDE_SESSION_ROOT` (the shared root) and overrides `$CLAUDE_SESSION_DIR` to point at the private dir.
3. **During the session**, any tool can read/write files in that directory. The `session-*` CLI tools accept `--shared` (as a leading flag) to write to the shared root from within a subagent.
4. **SessionEnd** hook removes the entire session directory (including all private namespaces).

Writes are atomic (temp file + rename), so a concurrent reader never observes
an empty or partially written value — including a multi-item `session-list
add`, which is visible all-or-nothing. Every mutating command
(`session-set`/`-del`/`-incr`/`-decr` and `session-list`
`add`/`rm`/`rm-all`/`clear`/`pop`) additionally takes a per-key lock, so
parallel subagents can safely hammer the same shared key.

All tools accept `--help`/`-h`. To use a key that itself starts with `--`,
terminate option parsing with a leading `--` (POSIX convention):
`session-get -- --weird-key`.

Note: most systems periodically clean their temp directory (macOS reaps
entries unaccessed for a few days), so an extremely long-lived idle session
could lose its store. This is scratch storage; don't keep anything in it that
can't be regenerated.

## Requirements

- Claude Code 2.1+
- bash, plus standard POSIX utilities (`find`, `grep`, `awk`)
- `jq` (used by the SubagentStart hook to read the agent id; without it each
  subagent still gets an isolated namespace, just under a generated UUID)
- Per-key locking uses `flock(1)` when available, otherwise `perl`
  (both ship on macOS and virtually all Linux)

## Testing

```
./tests/run-tests.sh                          # full suite
SESSION_STORE_NO_FLOCK=1 ./tests/run-tests.sh # force the perl lock path
```

CI runs shellcheck plus the suite on Linux and macOS, including a macOS pass
under the system bash 3.2.

## License

MIT
