#!/usr/bin/env bash
# Test suite for claude-session-store. Plain bash, no framework dependency,
# and bash-3.2-safe (macOS /bin/bash) like the tools it tests.
#
# Run:  ./tests/run-tests.sh
# Force the perl lock path on systems that have flock(1):
#       SESSION_STORE_NO_FLOCK=1 ./tests/run-tests.sh
set -u

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
PATH="$ROOT/bin:$PATH"
export PATH

# Setup failures must be fatal: with an empty $WORK the whole suite would
# cascade into meaningless failures against paths like "/store-1".
WORK="$(mktemp -d "${TMPDIR:-/tmp}/session-store-tests.XXXXXX")" || {
  echo "FATAL: could not create test workspace" >&2
  exit 1
}
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
GROUP=""

group() { GROUP="$1"; printf '== %s\n' "$1"; }
pass()  { PASS=$((PASS + 1)); }
fail()  { FAIL=$((FAIL + 1)); printf '  FAIL [%s] %s\n' "$GROUP" "$1"; }

# assert_eq DESC EXPECTED ACTUAL
assert_eq() {
  if [ "$2" = "$3" ]; then
    pass
  else
    fail "$1: expected $(printf '%q' "$2"), got $(printf '%q' "$3")"
  fi
}

# assert_rc DESC EXPECTED_RC CMD [ARGS...]
assert_rc() {
  local desc="$1" want="$2" rc=0
  shift 2
  "$@" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq "$want" ]; then
    pass
  else
    fail "$desc: expected rc $want, got rc $rc"
  fi
}

# assert_contains DESC NEEDLE HAYSTACK
assert_contains() {
  case "$3" in
    *"$2"*) pass ;;
    *) fail "$1: output does not contain $(printf '%q' "$2")" ;;
  esac
}

# assert_file DESC PATH        (file exists)
assert_file() {
  if [ -f "$2" ]; then pass; else fail "$1: expected file $2 to exist"; fi
}

# assert_no_path DESC PATH     (nothing exists at PATH)
assert_no_path() {
  if [ ! -e "$2" ]; then pass; else fail "$1: expected $2 to be absent"; fi
}

STORE_N=0
new_store() {
  STORE_N=$((STORE_N + 1))
  CLAUDE_SESSION_DIR="$WORK/store-$STORE_N"
  export CLAUDE_SESSION_DIR
  mkdir -p "$CLAUDE_SESSION_DIR"
  unset CLAUDE_SESSION_ROOT 2>/dev/null || true
}

# ---------------------------------------------------------------- key-value

group "kv: set/get/del round trips"
new_store
session-set k1 "hello world"
assert_eq "simple round trip" "hello world" "$(session-get k1)"
session-set k1 "overwritten"
assert_eq "overwrite" "overwritten" "$(session-get k1)"
assert_rc "get missing key" 1 session-get nope
session-del k1
assert_rc "get after del" 1 session-get k1
assert_rc "del missing key is ok" 0 session-del k1

printf 'line1\nline2\n' | session-set multi -
assert_eq "stdin multi-line value" "$(printf 'line1\nline2')" "$(session-get multi)"

session-set unicode "2♠ 3♠ café"
assert_eq "unicode value" "2♠ 3♠ café" "$(session-get unicode)"

group "kv: key validation"
new_store
assert_rc "space in key" 1 session-set "bad key" v
assert_rc "slash in key" 1 session-set "a/b" v
assert_rc "traversal key" 1 session-set "../escape" v
assert_rc "empty key" 1 session-set "" v
assert_rc "newline in key" 1 session-set "$(printf 'a\nb')" v
assert_rc "valid key chars" 0 session-set "A-z_09" v

group "kv: flag parsing"
new_store
session-set k2 --shared
assert_eq "literal --shared as value" "--shared" "$(session-get k2)"
session-set --shared k3 v3
assert_eq "--shared in main session writes same store" "v3" "$(session-get k3)"
session-set -- --weird-key wv
assert_eq "-- escapes a leading-dash key" "wv" "$(session-get -- --weird-key)"
session-set -- --help hv
assert_eq "-- escapes literal --help key" "hv" "$(session-get -- --help)"

group "counters"
new_store
assert_eq "incr initializes to 1" "1" "$(session-incr c)"
assert_eq "incr amount" "11" "$(session-incr c 10)"
assert_eq "decr" "10" "$(session-decr c)"
assert_eq "negative amount" "-5" "$(session-incr neg -5)"
session-set zeros 007
assert_eq "leading zeros normalized" "8" "$(session-incr zeros)"
session-set big 9007199254740993
assert_eq "int64-exact arithmetic" "9007199254740994" "$(session-incr big)"
session-set str hello
assert_rc "incr non-integer value" 1 session-incr str
assert_rc "incr non-integer amount" 1 session-incr c abc

group "keys listing"
new_store
session-set alpha 1
session-set beta 2
session-incr gamma >/dev/null   # creates .locks as a side effect
assert_eq "sorted keys, .locks hidden" "alpha beta gamma" "$(session-keys | tr '\n' ' ' | sed 's/ $//')"
mkdir -p "$CLAUDE_SESSION_DIR/.ns/agent1"
assert_eq ".ns hidden from keys" "alpha beta gamma" "$(session-keys | tr '\n' ' ' | sed 's/ $//')"

# -------------------------------------------------------------------- lists

group "lists: add/rm/has/count/show/clear"
new_store
session-list deck add a b c b
assert_eq "count after add" "4" "$(session-list deck count)"
assert_eq "show preserves order" "$(printf 'a\nb\nc\nb')" "$(session-list deck show)"
assert_rc "has present" 0 session-list deck has b
assert_rc "has absent" 1 session-list deck has z
session-list deck rm b
assert_eq "rm removes first occurrence only" "$(printf 'a\nc\nb')" "$(session-list deck show)"
session-list deck add b
session-list deck rm-all b
assert_eq "rm-all removes every occurrence" "$(printf 'a\nc')" "$(session-list deck show)"
session-list deck clear
assert_eq "count after clear" "0" "$(session-list deck count)"
assert_rc "cleared key gone from keys" 1 session-get deck
assert_rc "newline item rejected" 1 session-list deck add "$(printf 'x\ny')"
assert_rc "unknown command" 1 session-list deck frobnicate
session-list dash add -- --shared
assert_rc "literal --shared as item" 0 session-list dash has -- --shared
session-list mid add a --shared b
assert_eq "mid-arg --shared is a positional item" "3" "$(session-list mid count)"

group "lists: set operations"
new_store
session-list all add a b c d e
session-list 'done' add c d
assert_eq "diff" "$(printf 'a\nb\ne')" "$(session-list all diff 'done')"
assert_eq "intersect" "$(printf 'c\nd')" "$(session-list all intersect 'done')"
assert_eq "union" "$(printf 'a\nb\nc\nd\ne')" "$(session-list all union 'done')"
assert_eq "diff against missing key" "$(printf 'a\nb\nc\nd\ne')" "$(session-list all diff nothere)"

group "lists: pop"
new_store
assert_rc "pop empty list" 1 session-list q pop
session-list q add first second third
assert_eq "pop returns head" "first" "$(session-list q pop)"
assert_eq "pop again" "second" "$(session-list q pop)"
assert_eq "pop last" "third" "$(session-list q pop)"
assert_rc "pop drained list" 1 session-list q pop
assert_eq "drained key removed" "" "$(session-keys)"

# -------------------------------------------------------------- namespacing

group "subagent namespacing (simulated env)"
NSROOT="$WORK/nsroot"
NSPRIV="$NSROOT/.ns/agentA"
mkdir -p "$NSPRIV"
export CLAUDE_SESSION_ROOT="$NSROOT"
export CLAUDE_SESSION_DIR="$NSPRIV"
session-set priv pv
assert_file "default write lands in private dir" "$NSPRIV/priv"
assert_no_path "default write not in shared root" "$NSROOT/priv"
session-set --shared shr sv
assert_file "--shared write lands in root" "$NSROOT/shr"
assert_rc "shared key invisible to private get" 1 session-get shr
assert_eq "--shared get reads root" "sv" "$(session-get --shared shr)"
session-list --shared jobs add j1 j2
assert_eq "--shared list in root" "2" "$(session-list --shared jobs count)"
assert_eq "private list empty" "0" "$(session-list jobs count)"
unset CLAUDE_SESSION_ROOT

# --------------------------------------------------------------------- help

group "help"
for tool in session-set session-get session-del session-incr session-decr session-keys session-list; do
  out="$("$tool" --help 2>&1)" && rc=0 || rc=$?
  assert_eq "$tool --help exit code" "0" "$rc"
  assert_contains "$tool --help prints usage" "Usage: $tool" "$out"
  assert_rc "$tool -h" 0 "$tool" -h
  assert_rc "$tool --help without plugin env" 0 env -u CLAUDE_SESSION_DIR "$tool" --help
done
assert_rc "no args shows usage with rc 1" 1 session-set

# -------------------------------------------------------------- concurrency

# run_concurrency_tests LABEL — parallel writers must serialize correctly.
run_concurrency_tests() {
  local label="$1" i w total
  group "concurrency ($label)"

  new_store
  i=0
  while [ "$i" -lt 30 ]; do
    session-incr pc >/dev/null 2>&1 &
    i=$((i + 1))
  done
  wait
  assert_eq "30 parallel incr" "30" "$(session-get pc)"

  new_store
  w=0
  while [ "$w" -lt 4 ]; do
    (
      i=0
      while [ "$i" -lt 10 ]; do
        session-list bag add "w${w}-i${i}"
        i=$((i + 1))
      done
    ) &
    w=$((w + 1))
  done
  wait
  assert_eq "4x10 parallel list add" "40" "$(session-list bag count)"

  new_store
  i=1
  while [ "$i" -le 40 ]; do
    session-list q add "item-$i"
    i=$((i + 1))
  done
  w=0
  while [ "$w" -lt 4 ]; do
    (
      while item="$(session-list q pop 2>/dev/null)"; do
        printf '%s\n' "$item" >> "$WORK/popped-$label.$w"
      done
    ) &
    w=$((w + 1))
  done
  wait
  total="$(cat "$WORK/popped-$label".* | wc -l | tr -d ' ')"
  assert_eq "parallel pop drains everything" "40" "$total"
  assert_eq "parallel pop never duplicates" "40" \
    "$(cat "$WORK/popped-$label".* | sort -u | wc -l | tr -d ' ')"
}

run_concurrency_tests "default"
SESSION_STORE_NO_FLOCK=1
export SESSION_STORE_NO_FLOCK
run_concurrency_tests "perl"
unset SESSION_STORE_NO_FLOCK

group "atomic writes (no torn reads)"
new_store
EXPECT="a-reasonably-long-value-that-would-tear-if-writes-truncated-in-place"
session-set av "$EXPECT"
(
  i=0
  while [ "$i" -lt 100 ]; do
    session-set av "$EXPECT" >/dev/null 2>&1
    i=$((i + 1))
  done
) &
WRITER=$!
bad=0
i=0
while [ "$i" -lt 100 ]; do
  v="$(session-get av)" || bad=$((bad + 1))
  [ "$v" = "$EXPECT" ] || bad=$((bad + 1))
  i=$((i + 1))
done
wait "$WRITER"
assert_eq "reader never sees empty/partial value" "0" "$bad"

new_store
(
  i=0
  while [ "$i" -lt 50 ]; do
    session-list pairs add x y >/dev/null 2>&1
    i=$((i + 1))
  done
) &
WRITER=$!
bad=0
i=0
while [ "$i" -lt 60 ]; do
  n="$(session-list pairs count)"
  [ $((n % 2)) -eq 0 ] || bad=$((bad + 1))
  i=$((i + 1))
done
wait "$WRITER"
assert_eq "multi-item add is all-or-nothing for readers" "0" "$bad"

# -------------------------------------------------------------------- hooks

group "hooks: session-start"
HB="$WORK/hookbase"
mkdir -p "$HB"
ENVF="$WORK/envfile"
: > "$ENVF"
env TMPDIR="$HB/" CLAUDE_ENV_FILE="$ENVF" CLAUDE_CODE_SESSION_ID="sess-abc-123" \
  "$ROOT/hooks/session-start"
SDIR="$HB/claude-session-sess-abc-123"
if [ -d "$SDIR" ]; then pass; else fail "session dir not created"; fi
assert_eq "session dir mode 0700" "700" \
  "$(perl -e 'printf "%o", (stat($ARGV[0]))[2] & 07777' "$SDIR")"
assert_eq "env file exports CLAUDE_SESSION_DIR" "$SDIR" \
  "$(bash -c ". '$ENVF'; printf '%s' \"\$CLAUDE_SESSION_DIR\"")"
# Reset PATH inside the probe shells so the harness's own prepend can't mask
# a broken env-file line.
assert_eq "env file puts plugin bin on PATH" "$ROOT/bin/session-set" \
  "$(bash -c "PATH=/usr/bin:/bin; export PATH; . '$ENVF'; command -v session-set")"
env TMPDIR="$HB/" CLAUDE_ENV_FILE="$ENVF" CLAUDE_CODE_SESSION_ID="sess-abc-123" \
  "$ROOT/hooks/session-start"
assert_eq "PATH line not duplicated on re-run" "1" "$(grep -c 'export PATH=' "$ENVF")"
assert_eq "sourcing twice keeps PATH entry single" "1" \
  "$(bash -c "PATH=/usr/bin:/bin; export PATH; . '$ENVF'; . '$ENVF'; printf '%s' \":\$PATH:\" | grep -o \":$ROOT/bin:\" | wc -l | tr -d ' '")"

chmod 755 "$SDIR"
env TMPDIR="$HB/" CLAUDE_ENV_FILE="$ENVF" CLAUDE_CODE_SESSION_ID="sess-abc-123" \
  "$ROOT/hooks/session-start"
assert_eq "pre-existing dir mode re-asserted to 0700" "700" \
  "$(perl -e 'printf "%o", (stat($ARGV[0]))[2] & 07777' "$SDIR")"

LINES_BEFORE="$(wc -l < "$ENVF" | tr -d ' ')"
assert_rc "unsafe session id skipped" 0 \
  env TMPDIR="$HB/" CLAUDE_ENV_FILE="$ENVF" CLAUDE_CODE_SESSION_ID="../evil" "$ROOT/hooks/session-start"
assert_rc "empty session id skipped" 0 \
  env TMPDIR="$HB/" CLAUDE_ENV_FILE="$ENVF" CLAUDE_CODE_SESSION_ID= "$ROOT/hooks/session-start"
assert_rc "missing env file var skipped" 0 \
  env TMPDIR="$HB/" CLAUDE_ENV_FILE= CLAUDE_CODE_SESSION_ID="sess-abc-123" "$ROOT/hooks/session-start"
assert_eq "skipped runs write nothing to env file" "$LINES_BEFORE" "$(wc -l < "$ENVF" | tr -d ' ')"

group "hooks: stale-dir GC"
STALE="$HB/claude-session-stale1"
RECENT="$HB/claude-session-recent1"
ACTIVE="$HB/claude-session-active1"
PROTECTED="$WORK/protected"
mkdir -p "$STALE" "$RECENT" "$ACTIVE" "$PROTECTED"
echo keep > "$PROTECTED/f"
ln -s "$PROTECTED" "$HB/claude-session-linked"
# STALE: old root, nothing inside → reap. ACTIVE: old root but a recently
# written key inside (a long-running session that never re-fired
# SessionStart) → must survive; root-dir mtime alone is not liveness.
echo counter > "$ACTIVE/somekey"
touch -t 202001010101 "$STALE" "$ACTIVE"
env TMPDIR="$HB/" CLAUDE_ENV_FILE="$ENVF" CLAUDE_CODE_SESSION_ID="sess-abc-123" \
  "$ROOT/hooks/session-start"
assert_no_path "stale dir reaped" "$STALE"
if [ -d "$RECENT" ]; then pass; else fail "recent dir must survive GC"; fi
assert_file "active session with recent key survives GC" "$ACTIVE/somekey"
assert_file "symlink target never followed" "$PROTECTED/f"

group "hooks: session-end"
env TMPDIR="$HB/" CLAUDE_CODE_SESSION_ID="sess-abc-123" "$ROOT/hooks/session-end"
assert_no_path "session dir removed" "$SDIR"
assert_rc "empty session id is a no-op" 0 \
  env TMPDIR="$HB/" CLAUDE_CODE_SESSION_ID= "$ROOT/hooks/session-end"
assert_rc "unsafe session id is a no-op" 0 \
  env TMPDIR="$HB/" CLAUDE_CODE_SESSION_ID="../evil" "$ROOT/hooks/session-end"

group "hooks: subagent-start"
if command -v jq >/dev/null 2>&1; then
  SROOT="$HB/claude-session-subroot"
  mkdir -p "$SROOT"
  ENVF2="$WORK/envfile2"
  : > "$ENVF2"
  printf '{"agent_id":"agentA"}' | \
    env CLAUDE_ENV_FILE="$ENVF2" CLAUDE_SESSION_DIR="$SROOT" "$ROOT/hooks/subagent-start"
  assert_eq "subagent env exports root/ns/private dir" \
    "$SROOT|agentA|$SROOT/.ns/agentA" \
    "$(bash -c ". '$ENVF2'; printf '%s|%s|%s' \"\$CLAUDE_SESSION_ROOT\" \"\$CLAUDE_AGENT_NS\" \"\$CLAUDE_SESSION_DIR\"")"
  if [ -d "$SROOT/.ns/agentA" ]; then pass; else fail "private dir not created"; fi

  ENVF3="$WORK/envfile3"
  : > "$ENVF3"
  printf '{"agent_id":"../evil"}' | \
    env CLAUDE_ENV_FILE="$ENVF3" CLAUDE_SESSION_DIR="$SROOT" "$ROOT/hooks/subagent-start"
  NS="$(bash -c ". '$ENVF3'; printf '%s' \"\$CLAUDE_AGENT_NS\"")"
  case "$NS" in
    '' | *[!a-zA-Z0-9_-]* ) fail "unsafe agent id must fall back to a safe generated id (got '$NS')" ;;
    * ) pass ;;
  esac
  if [ -d "$SROOT/.ns/$NS" ]; then pass; else fail "fallback private dir not created"; fi
  assert_no_path "no traversal outside .ns" "$SROOT/evil"

  ENVF4="$WORK/envfile4"
  : > "$ENVF4"
  printf '{"agent_id":"agentB"}' | \
    env CLAUDE_ENV_FILE="$ENVF4" CLAUDE_SESSION_ROOT="$SROOT" \
        CLAUDE_SESSION_DIR="$SROOT/.ns/agentA" "$ROOT/hooks/subagent-start"
  assert_eq "nested subagent anchors under real root" "$SROOT/.ns/agentB" \
    "$(bash -c ". '$ENVF4'; printf '%s' \"\$CLAUDE_SESSION_DIR\"")"
else
  printf '  (skipped: jq not installed)\n'
fi
assert_rc "subagent-start without env file is a no-op" 0 \
  env CLAUDE_ENV_FILE= CLAUDE_SESSION_DIR="$WORK" "$ROOT/hooks/subagent-start"

# ------------------------------------------------------------------ summary

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
