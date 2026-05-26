---
description: >
  Use when you need to persist state across tool calls within a session — game state, running
  totals, intermediate results, or any scratch data that should not outlive the conversation.
  TRIGGER when the user says or implies ongoing state: "keep track of", "remember", "maintain",
  "don't lose", "running total", "how many so far", "what's left", or any multi-turn activity
  with mutable state (card games, inventories, scoreboards, queues, counters).
  Also invoke proactively alongside other skills that produce stateful results (e.g. randkit draws
  from a deck, sequential dice games, elimination brackets) — if the output of one turn constrains
  the next, store it here.
---

# Session Store Skill

You have access to session-scoped scratch storage via `$CLAUDE_SESSION_DIR`. Data stored here persists for the lifetime of the session and is automatically cleaned up when the session ends.

## Tools

### Key-Value

| Command | Purpose |
|---------|---------|
| `session-set KEY VALUE` | Store a value (or pipe with `VALUE=-`) |
| `session-get KEY` | Retrieve a value (exits 1 if missing) |
| `session-del KEY` | Delete a key |
| `session-incr KEY [AMOUNT]` | Increment numeric key by AMOUNT (default 1), init 0 if missing |
| `session-decr KEY [AMOUNT]` | Decrement numeric key by AMOUNT (default 1), init 0 if missing |
| `session-keys` | List all stored keys |

### Lists

`session-list KEY COMMAND [ARGS...]` — manage ordered collections stored under a key. Items are stored newline-separated.

| Command | Purpose |
|---------|---------|
| `session-list KEY add ITEM [ITEM...]` | Append items to the list |
| `session-list KEY rm ITEM [ITEM...]` | Remove first occurrence of each item |
| `session-list KEY rm-all ITEM [ITEM...]` | Remove all occurrences of each item |
| `session-list KEY has ITEM` | Exit 0 if item exists, 1 otherwise |
| `session-list KEY count` | Print number of items |
| `session-list KEY show` | Print all items (one per line) |
| `session-list KEY clear` | Remove all items (deletes the key) |
| `session-list KEY diff OTHER` | Items in KEY that are not in OTHER |
| `session-list KEY intersect OTHER` | Items in both KEY and OTHER |
| `session-list KEY union OTHER` | Items in either KEY or OTHER (deduplicated) |

**Example — card deck tracking:**
```bash
# Initialize a deck
session-list remaining add A♠ 2♠ 3♠ 4♠ 5♠ 6♠ 7♠ 8♠ 9♠ 10♠ J♠ Q♠ K♠

# Draw cards: remove from remaining, add to drawn
session-list remaining rm J♠ 9♠ K♠
session-list drawn add J♠ 9♠ K♠

# Check state
session-list remaining count   # → 10
session-list remaining has Q♠  # → exit 0 (still there)
session-list drawn show        # → J♠\n9♠\nK♠
```

**Example — task queue:**
```bash
session-list todo add "fix tests" "update docs" "deploy"
session-list todo rm "fix tests"
session-list done add "fix tests"
session-list todo count  # → 2
session-list todo diff done   # → "update docs"\n"deploy"
```

**Example — set operations:**
```bash
session-list all add endpoints auth users billing health
session-list tested add auth health

session-list all diff tested       # → billing\nendpoints\nusers
session-list all intersect tested  # → auth\nhealth
session-list tested union all      # → auth\nbilling\nendpoints\nhealth\nusers
```

## Direct file access

You can also read/write files directly in `$CLAUDE_SESSION_DIR`:

```bash
echo "data" > "$CLAUDE_SESSION_DIR/myfile"
cat "$CLAUDE_SESSION_DIR/myfile"
```

## Rules

1. **Use this for state that only matters within the current session** — game state, running totals, intermediate results, deck tracking, etc.
2. **Keys are flat** — alphanumeric, hyphens, underscores only. No subdirectories via the CLI tools (but you can mkdir inside `$CLAUDE_SESSION_DIR` directly if needed).
3. **Values are plain text.** For structured data, store JSON and parse with `jq`.
4. **Don't store secrets.** The directory lives in `/tmp` and is world-readable.
5. **Check before assuming.** Use `session-get` and check the exit code before using a value that may not exist yet.
6. **Never compute complements manually.** When tracking a subset drawn from a known universe (deck, pool, roster), initialize the full collection with `add` first, then use `rm` to remove items as they're selected. Do not mentally subtract and type out the remainder — that's error-prone.
