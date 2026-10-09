#!/usr/bin/env bash
#
# forbidden-syntax.sh - fail on host-access tunnels, non-loopback port publishing,
# container-runtime drift and other-OS mentions.
#
# Policy: host access is minikube NodePorts published on 127.0.0.1 at profile
# creation (--ports=127.0.0.1:<hostPort>:<nodePort>). Tunnels break or
# disconnect, so these are forbidden everywhere in the repo:
#   SSH tunnels (ssh -L), kubectl port-forward / proxy, socat, minikube tunnel,
#   minikube service --url, any use of the word "tunnel" or the old helper
#   names, and bare --ports=a:b (binds 0.0.0.0; use a 127.0.0.1: prefix).
# Host scope: supported hosts are Fedora or RHEL, bare metal or VM. No other operating system,
# distribution, WSL, or OS-specific tool is mentioned anywhere (scan 6). A line
# that is `runs-on: ubuntu-latest` or `os: [ubuntu-latest]` (a CI runner label,
# optionally followed by a trailing # comment) is exempt; the comment is still
# scanned.
#
# Files scanned: the git-tracked files of ROOT_DIR (`git -C "$ROOT_DIR" ls-files`,
# which skips untracked and ignored files such as _site/ copies). If ROOT_DIR is
# not the top of a git checkout (test fixtures), or git is missing, it falls
# back to find with the excludes below. Scans (relative to ROOT_DIR, which
# defaults to the repo root):
#   1. tunnel / port-forward / ssh -L/-R/-D / kubectl proxy / socat patterns.
#      `ssh .*-L ` is matched case-insensitively, so `ssh -l user host` (login
#      name) also fails; reword it or mark the line forbidden-ok. The
#      case-sensitive `ssh -...L|R|D` forms are listed separately.
#   2. case-sensitive legacy helper names
#   3. --ports values lacking a 127.0.0.1: prefix. Shell expansions are ignored,
#      except a ${X:-a:b} default, which must carry the prefix. Handles a space
#      after a comma and a `--ports \` continuation onto the next line. Applies
#      to every tracked text file (python3 engine) and to pptx text.
#   4. scans 1, 3, 5 and 6 inside every tracked *.pptx slides, notes, layouts
#      and masters (fails if unzip is missing)
#   5. container runtime scope: podman / rootless / CRI-O / crio / crun /
#      MINIKUBE_ROOTLESS / the retired localhost:5000 registry name outside the
#      CRC appendix allowlist (empty here; the minikube path is Docker Engine +
#      containerd)
#   6. other-OS mentions (case-insensitive list plus case-sensitive Windows,
#      Mac etc.). Before matching it strips the CSS tokens
#      -moz-osx-font-smoothing, -apple-system and Segoe UI, and the tag of a
#      container image reference (name:alpine, name:3.20-alpine; the image name
#      is still scanned). Kafka "Tumbling/Hopping/Sliding/Session/Time/Join/Grace
#      Windows" and "Windows of N seconds" are removed before the capitalised
#      Windows check; standalone Windows and Windows 11 still fail.
#
# A line that states the prohibition (or must mention a forbidden term) carries
# the marker `forbidden-ok` in its text (a marker in the path does not count);
# so does a line that scopes podman to the CRC appendix, or records a historical
# lesson (HTML comment in Markdown, trailing comment in shell). Always excluded:
# _plans/archive/, *.archive.md, *.lock, package-lock.json, poetry.lock, binary
# files and this script. The find fallback also excludes .git, .claude (local
# tool settings), node_modules, _site, .jekyll-cache, __pycache__, .venv, venv,
# vendor and .pytest_cache.
# Exit 1 on any hit, or if a required tool (grep, find, sed, sort) is missing or
# errors; otherwise print "forbidden-syntax: OK".

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${ROOT_DIR:-$(cd "$HERE/.." && pwd)}"
ROOT_DIR="$(cd "$ROOT_DIR" && pwd -P)"
cd "$ROOT_DIR"

die() { printf 'forbidden-syntax: FAILED: %s\n' "$*" >&2; exit 1; }
for tool in grep find sed sort; do
    command -v "$tool" >/dev/null 2>&1 || die "required tool not found: $tool"
done

fail=0
total=0
report() { # <label> <hits>
    local nl_only="${2//[!$'\n']/}"
    printf 'forbidden-syntax: %s\n' "$1"
    printf '%s\n' "$2" | sed 's/^/    /'
    fail=1
    total=$((total + ${#nl_only} + 1))
}

# gq <grep args> — grep where exit 1 (no match) is fine and exit >= 2 is fatal.
gq() {
    local rc=0
    grep "$@" || rc=$?
    (( rc <= 1 )) || die "grep failed (exit $rc)"
}

# Common filter: drop archive paths and allow-marked lines. `forbidden-ok` counts
# only in the line text (after path:line:), never in the path.
filter() { gq -vE -e '^scripts/forbidden-syntax\.sh:' -e '^_plans/archive/' -e '\.archive\.md:' -e '^[^:]*:[0-9]+:.*forbidden-ok'; }

# ─── File list ──────────────────────────────────────────────────────────────
# Tracked files when ROOT_DIR is the top of a git checkout, else find + excludes.
FAILMARK=$'\001listing-failed'
path_excluded() { # <relpath> → 0 if never scanned
    case "$1" in
        _plans/archive/*|*.archive.md|*.lock|package-lock.json|*/package-lock.json|poetry.lock|*/poetry.lock|forbidden-syntax.sh|*/forbidden-syntax.sh) return 0 ;;
    esac
    return 1
}
FILES=()
build_file_list() {
    local top f raw=()
    if command -v git >/dev/null 2>&1 \
        && top="$(git -C "$ROOT_DIR" rev-parse --show-toplevel 2>/dev/null)" \
        && [[ "$(cd "$top" && pwd -P)" == "$ROOT_DIR" ]]; then
        mapfile -d '' -t raw < <(git -C "$ROOT_DIR" ls-files -z || printf '%s\0' "$FAILMARK")
    else
        mapfile -d '' -t raw < <( { find . \( -name .git -o -name .claude -o -name node_modules \
                -o -name __pycache__ -o -name .venv -o -name venv -o -name vendor \
                -o -name .pytest_cache -o -name _site -o -name .jekyll-cache \) -prune \
                -o -type f -print0 | sort -z; } || printf '%s\0' "$FAILMARK")
    fi
    for f in "${raw[@]}"; do
        [[ "$f" == "$FAILMARK" ]] && die "file listing failed (git ls-files or find)"
        f="${f#./}"
        [[ -f "$f" ]] || continue            # deleted, dangling link or submodule
        path_excluded "$f" && continue
        FILES+=("$f")
    done
}
build_file_list

# only_ext <out-array> <glob>... → FILES entries matching any glob
only_ext() {
    local -n out="$1"; shift
    local f g
    out=()
    for f in "${FILES[@]}"; do
        for g in "$@"; do
            if [[ "$f" == $g ]]; then out+=("$f"); break; fi
        done
    done
    return 0
}

# gr_in <array-name> <grep-flags> <regex> → "path:line:text" over those files.
gr_in() {
    local -n arr="$1"
    local i rc
    for (( i = 0; i < ${#arr[@]}; i += 400 )); do
        rc=0
        grep -HnI "$2" -e "$3" -- "${arr[@]:i:400}" || rc=$?
        (( rc <= 1 )) || die "grep failed (exit $rc)"
    done
}
gr() { gr_in FILES "$@"; }

# Patterns are built from fragments so the script never matches itself.
tn="tun""nel"
pf="port-?for""ward"
mk="minikube( +-p +[^ ]+)?"
re1="$tn|$pf|port_for""ward|port for""ward|forward""Ports|kubectl +pro""xy|\\bso""cat\\b|ssh .*-L |$mk +$tn|minikube .*service .*--url"
# Case-sensitive variants (ssh -l is a login name; see the header note on re1).
# -R and -D are remote and dynamic forwarding.
re1cs="ssh +-[A-Za-z]*L|ssh +-[A-Za-z]*[RD] |-L[0-9]"
re2="ensure_$tn|${tn}_port_for|$tn-services|${tn}s\\.sh"

# Scan 3 engine. Reads stdin: a list of file paths (default mode), or with
# argv[1] == "-" the text to scan, labelled argv[2]. Prints path:line:text.
read -r -d '' SCAN3_PY <<'PYEOF' || true
import re, sys

QUOTES = ("\"", "'")

def bare(it):
    it = it.strip().rstrip("`).;")
    if not it or "$" in it:
        return False
    return bool(re.fullmatch(r"[0-9]+", it) or ":" in it) and not it.startswith("127.0.0.1:")

DEF = re.compile(r"\$\{[A-Za-z_0-9]+:?[-=+]([^}]*)\}")
TOK = re.compile(r"[^\s\"']*")
FLAG = re.compile(r"--ports(?:=|[ \t]+|$)")

def bad_value(val):
    defaults = DEF.findall(val)
    items = DEF.sub("EXP", val).split(",")
    for d in defaults:
        items += d.split(",")
    return any(bare(i) for i in items)

def line_bad(lines, i):
    line = lines[i]
    if "forbidden-ok" in line:
        return False
    for m in FLAG.finditer(line):
        r = line[m.end():].strip()
        if r in ("", "\\"):
            # value on the next line (line continuation)
            if i + 1 >= len(lines) or "forbidden-ok" in lines[i + 1]:
                continue
            r = lines[i + 1].strip()
        r = re.sub(r"\s*,\s*", ",", r)   # whitespace around commas
        if r[:1] in QUOTES:
            r = r[1:]
        val = TOK.match(r).group()
        rest = r[len(val):]
        while val.endswith(","):
            # a space after the comma: the next token continues the list
            rest = rest.lstrip(" \t")
            if rest[:1] in QUOTES:
                rest = rest[1:]
            tok = TOK.match(rest).group()
            if not tok:
                break
            val += tok
            rest = rest[len(tok):]
        if bad_value(val):
            return True
    return False

def scan(label, text):
    lines = text.split("\n")
    for i in range(len(lines)):
        if line_bad(lines, i):
            print("%s:%d:%s" % (label, i + 1, lines[i].strip()))

if sys.argv[1] == "-":
    scan(sys.argv[2], sys.stdin.read())
else:
    for path in sys.stdin.read().split("\n"):
        if not path or path.startswith("_plans/archive/") or path.endswith(".archive.md"):
            continue
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                scan(path, fh.read())
        except OSError:
            pass
PYEOF
if ! command -v python3 >/dev/null 2>&1; then
    die "required tool not found: python3 (needed by scan 3)"
fi

# Scan 5 / 6 patterns. Fragments keep the script from matching itself.
pm="pod""man"
re5="$pm|rootless|cri-o|\\bcrio\\b|\\bcrun\\b|MINIKUBE_ROOTLESS|localhost:5000"
o1="mac ?""os|os ?""x|os""x|dar""win|w""sl2?|ubu""ntu|deb""ian|alp""ine|cent""os|open""suse|su""se|linux ""mint"
o2="col""ima|rancher"" desktop|orb""stack|home""brew|choco""latey|win""get|power""shell|hyper""-v"
o3="rocky ?""linux|alma""linux|free""bsd|pac""man|zyp""per|apple"" silicon|mac""book|win ?1[01]|win""dows ?1[01]|arch ?""linux|nix""os|gen""too"
re6i="\\b($o1|$o2|$o3)\\b|\\.w""slconfig|%user""profile%|%app""data%|\\bchoco(latey)? +install|\\bscoop +install|\\bapt(-get)? +(-y +)?(install|update|upgrade)|\\bbrew +(--cask +)?(install|tap|upgrade|bundle)|C:\\\\Users"
re6cs="\\bWin""dows\\b|\\bWIN""DOWS\\b|\\bMac\\b|runs-on:.*win""dows|runs-on:.*mac""os"
msg6='other-OS mention (supported hosts are Fedora or RHEL, bare metal or VM)'
css_tokens=("-moz-os""x-font-smoothing" "-apple""-system" "'Segoe"" UI'" "\"Segoe"" UI\"")

# strip_css <text> → text without the allowed CSS tokens and container image tags
strip_css() {
    local t="$1" k
    for k in "${css_tokens[@]}"; do t="${t//"$k"/}"; done
    # Container image tags (postgres:alp''ine, postgres:16-alp''ine) name an image,
    # not a host OS. Only the tag after the colon is removed; the name stays scanned.
    t="$(sed -E 's#([A-Za-z0-9./_-]+):([A-Za-z0-9._-]*-)?alp''ine[A-Za-z0-9._-]*#\1#g' <<<"$t")"
    printf '%s' "$t"
}

# strip_kafka <text> → text without Kafka Streams window prose. Only the
# capitalised-Windows check (re6cs) runs on this; re6i runs on the unstripped
# text, so "Join Windows 11" still fails.
strip_kafka() {
    sed -E -e 's/\b(tumbling|hopping|sliding|session|time|join|grace) +windows?\b//Ig' \
           -e 's/\bwindows of ([0-9]+|N) +(milli)?(seconds?|minutes?|hours?)\b//Ig' <<<"$1"
}

# os_hits → reads "path:line:text" on stdin; prints lines that still match scan 6
# after dropping CI runner labels (their trailing comment is still scanned), the
# allowed CSS tokens, image tags and Kafka window prose.
os_hits() {
    local line text t2
    local lbl_re='^[[:space:]]*(-[[:space:]]+)?(runs-on:[[:space:]]*|os:[[:space:]]*\[[[:space:]]*)ubu''ntu-latest[[:space:]]*\]?[[:space:]]*(#.*)?$'
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        text="${line#*:*:}"
        if [[ "$text" =~ $lbl_re ]]; then
            text="${BASH_REMATCH[3]}"          # scan only the trailing comment
            [[ -z "$text" ]] && continue
        fi
        text="$(strip_css "$text")"
        t2="$(strip_kafka "$text")"
        if grep -qiE -e "$re6i" <<<"$text" || grep -qE -e "$re6cs" <<<"$t2"; then
            printf '%s\n' "$line"
        fi
    done
}

# Scan 1
hits="$(gr -iE "$re1" | filter)"
[[ -n "$hits" ]] && report 'tunnel / port-forward syntax (publish a NodePort at profile creation instead)' "$hits"
hits="$(gr -E "$re1cs" | filter)"
[[ -n "$hits" ]] && report 'ssh -L/-R/-D style forwarding (publish a NodePort at profile creation instead)' "$hits"

# Scan 2
hits="$(gr -E "$re2" | filter)"
[[ -n "$hits" ]] && report 'legacy tunnel helper names' "$hits"

# Scan 3: --ports values must start with 127.0.0.1: (shell expansions ignored,
# except a bare pair inside a ${X:-a:b} default). All text files.
hits="$(gr_in FILES -lE '--ports' | python3 -c "$SCAN3_PY" "@files" | filter)"
[[ -n "$hits" ]] && report '--ports value without 127.0.0.1: prefix (binds 0.0.0.0)' "$hits"

# Scan 5: container runtime scope. The allowlist (a grep -v -e '^<path>:' chain)
# is empty; a later change adds CRC appendix paths.
hits="$(gr -iE "$re5" | filter)"
[[ -n "$hits" ]] && report 'podman/rootless/CRI-O or the retired registry name outside the CRC appendix (the minikube path is Docker Engine + containerd)' "$hits"

# Scan 6: other-OS mentions.
hits="$( { gr -iE "$re6i"; gr -E "$re6cs"; } | filter | sort -u | os_hits)"
[[ -n "$hits" ]] && report "$msg6" "$hits"

nl=$'\n'   # literal newline: portable sed replacement (no GNU-only \n)
# Scan 4: slides, notes, layouts and masters inside pptx files.
pptx=()
only_ext pptx '*.pptx'  # tracked files only: _site/ copies are not scanned
if (( ${#pptx[@]} )); then
    if ! command -v unzip >/dev/null 2>&1; then
        report 'pptx scan impossible: unzip not found (install unzip; the gate must read the decks)' "${#pptx[@]} pptx file(s) not scanned"
    else
        for f in "${pptx[@]}"; do
            f="${f#./}"
            # Strip XML tags per paragraph so text split across <a:t> runs is rejoined.
            txt="$(unzip -p "$f" 'ppt/slides/*.xml' 'ppt/notesSlides/*.xml' \
                    'ppt/slideLayouts/*.xml' 'ppt/slideMasters/*.xml' \
                    'ppt/notesMasters/*.xml' 'ppt/handoutMasters/*.xml' 2>/dev/null \
                | sed -e "s#</a:p>#&\\${nl}#g" -e 's/<[^>]*>//g' || true)"
            txt="$(strip_css "$txt")"
            txt_kafka="$(strip_kafka "$txt")"
            m="$( { printf '%s\n' "$txt" | gq -ioE ".{0,30}($re1|$re5|$re6i).{0,30}"
                    printf '%s\n' "$txt" | gq -oE ".{0,30}($re1cs).{0,30}"
                    printf '%s\n' "$txt_kafka" | gq -oE ".{0,30}($re6cs).{0,30}"; } \
                | sort | uniq -c | sed -E 's/^ +//')"
            pbad="$(printf '%s\n' "$txt" | python3 -c "$SCAN3_PY" - "$f" | sed -E 's/^[^:]*:[0-9]+:/--ports without 127.0.0.1: prefix: /')"
            [[ -n "$pbad" ]] && m+="${m:+$'\n'}$pbad"
            [[ -n "$m" ]] && report "pptx contains forbidden syntax: $f" "$m"
        done
    fi
fi

if (( fail )); then
    echo "forbidden-syntax: FAILED ($total hit lines)"
    exit 1
fi
echo "forbidden-syntax: OK"
