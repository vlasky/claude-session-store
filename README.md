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

## How it works

1. **SessionStart** hook creates `/tmp/claude-session-<SESSION_ID>` and exports `$CLAUDE_SESSION_DIR` via `CLAUDE_ENV_FILE`.
2. **During the session**, any tool can read/write files in that directory.
3. **SessionEnd** hook removes the directory.

## Requirements

- Claude Code 2.1+
- bash, plus standard POSIX utilities (`find`, `grep`, `awk`)
- For safe concurrent writes (e.g. parallel subagents), every command that
  modifies a key (`session-set`/`-del`/`-incr`/`-decr` and `session-list`
  `add`/`rm`/`rm-all`/`clear`) takes a per-key lock using `flock(1)` when
  available, otherwise `perl` (both ship on macOS and virtually all Linux)

## License

MIT
