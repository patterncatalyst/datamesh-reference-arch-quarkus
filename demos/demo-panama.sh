#!/usr/bin/env bash
#
# demos/demo-panama.sh — "bare" toolchain demo (no compose, no cluster).
#
# Calls libc getpid() and strlen() from Java through the Foreign Function &
# Memory API (Project Panama, JEP 454, final in JDK 22) using the JBang
# script demos/jbang/PanamaFfm.java. Symbols come from the platform C
# library via Linker.nativeLinker().defaultLookup(), so this demo runs on
# Linux (Fedora or RHEL hosts).
#
# Asserts that the native results match what the JVM reports itself:
# getpid() == ProcessHandle.current().pid() and strlen(s) == the UTF-8 byte
# length of s.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/_demo.sh"

demo_begin "demo-panama"

# require() prints a generic install hint that does not apply to jbang, so
# this preflight carries its own.
if ! command -v jbang >/dev/null 2>&1; then
    fail "jbang is required for this demo but was not found on PATH. Install it with: curl -Ls https://sh.jbang.dev | bash (or: sdk install jbang) — then re-run this script. See https://www.jbang.dev/documentation/guide/latest/installation.html"
fi

SRC="${SCRIPT_DIR}/jbang/PanamaFfm.java"
[[ -f "$SRC" ]] || fail "source not found: $SRC"

LOGFILE="$(mktemp -t demo-panama-log-XXXXXX)"
trap 'rm -f "$LOGFILE"; _demo_exit_trap' EXIT

step "calling libc getpid() and strlen() through the FFM API"
narrate "jbang ${SRC#"${REPO_ROOT}"/}"

if ! jbang "$SRC" >"$LOGFILE" 2>&1; then
    cat "$LOGFILE" >&2
    fail "jbang PanamaFfm.java exited non-zero"
fi
cat "$LOGFILE"

pid_line="$(grep -E '^PANAMA_GETPID=[0-9]+ JVM_PID=[0-9]+$' "$LOGFILE" | head -n1)"
len_line="$(grep -E '^PANAMA_STRLEN=[0-9]+ JAVA_LENGTH=[0-9]+$' "$LOGFILE" | head -n1)"
[[ -n "$pid_line" ]] || fail "getpid output line missing from PanamaFfm output"
[[ -n "$len_line" ]] || fail "strlen output line missing from PanamaFfm output"

native_pid="${pid_line#PANAMA_GETPID=}"; native_pid="${native_pid%% *}"
jvm_pid="${pid_line##*JVM_PID=}"
native_len="${len_line#PANAMA_STRLEN=}"; native_len="${native_len%% *}"
java_len="${len_line##*JAVA_LENGTH=}"

[[ "$native_pid" == "$jvm_pid" ]] \
    || fail "getpid() returned $native_pid but the JVM reports pid $jvm_pid"
[[ "$native_len" == "$java_len" ]] \
    || fail "strlen() returned $native_len but the UTF-8 length is $java_len"

narrate "getpid()=$native_pid matches the JVM pid; strlen()=$native_len matches the UTF-8 byte length"
demo_ok
