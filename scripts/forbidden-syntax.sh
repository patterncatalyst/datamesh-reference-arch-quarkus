#!/usr/bin/env bash
#
# forbidden-syntax.sh - fail on host-access tunnels and non-loopback port publishing.
#
# Policy: host access is minikube NodePorts published on 127.0.0.1 at profile
# creation (--ports=127.0.0.1:<hostPort>:<nodePort>). Tunnels break or
# disconnect, so these are forbidden in docs, examples, scripts, site pages and decks:
#   SSH tunnels (ssh -L, ssh -vL, -L8080:...), kubectl port-forward, kubectl proxy,
#   socat, minikube tunnel, minikube service --url, port_forward / forwardPorts
#   settings, any use of the word "tunnel" or the old helper names, and bare
#   --ports=a:b (binds 0.0.0.0; use a 127.0.0.1: prefix).
# Host scope: supported hosts are Fedora or RHEL, bare metal or VM. No other
# operating system, distribution, WSL, or OS-specific tool is mentioned anywhere
# (scan 6). The only exempt CI label is the exact text `runs-on: ubuntu-latest`.
#
# Everything under the repo root is scanned (no target allowlist), minus the
# excludes listed below.
#
# Scans (relative to ROOT_DIR, which defaults to the repo root):
#   1. tunnel / port-forward patterns in text files (case-insensitive words,
#      case-sensitive ssh -L forms)
#   2. case-sensitive legacy helper names
#   3. --ports values lacking a 127.0.0.1: prefix. Handles a space after a comma,
#      a `--ports \` line continuation (the next line is the value), and a bare
#      pair inside a ${X:-a:b} default. Other shell expansions are ignored, they
#      come from node_ports_arg. Applies to every text file (not only *.sh,
#      *.md, *.html) and to pptx text.
#   4. the scan 1, 3, 5 and 6 patterns inside every *.pptx: slides, notes,
#      slide layouts and slide masters. Needs unzip; if a pptx exists and unzip
#      is missing the gate FAILS.
#   5. container runtime scope: podman / rootless / CRI-O / crio / crun /
#      MINIKUBE_ROOTLESS / the retired localhost:5000 registry name outside the
#      CRC appendix allowlist (the minikube path is Docker Engine + containerd)
#   6. other-OS mentions: a case-insensitive list, plus case-sensitive words
#      (Windows, WINDOWS, MacBook, Apple Silicon, Win10/Win11). Bare "mac"
#      (MAC address) and bare "arch" are deliberately not matched. Before
#      matching, `runs-on: ubuntu-latest` and the CSS font tokens
#      -moz-osx-font-smoothing, -apple-system, "Segoe UI" and container image
#      tags like postgres:16-alpine are stripped.
#
# A line that states the prohibition (or must mention a forbidden term) carries
# the marker `forbidden-ok`; so does a line that scopes podman to the CRC
# appendix, or records a historical lesson (the rootless-podman era) (HTML comment in Markdown, trailing comment in
# shell). Excluded: .git, node_modules, target, _site, .jekyll-cache,
# _plans/archive/, *.archive.md, *.lock, package-lock.json, the local
# .env, binary files, and this script.
# Exit 1 on any hit; otherwise print "forbidden-syntax: OK".

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${ROOT_DIR:-$(cd "$HERE/.." && pwd)}"
cd "$ROOT_DIR"

targets=(.)

fail=0
total=0
report() { # <label> <hits>
    printf 'forbidden-syntax: %s\n' "$1"
    printf '%s\n' "$2" | sed 's/^/    /'
    fail=1
    total=$((total + $(printf '%s\n' "$2" | wc -l)))
}

# Common filter: drop archive paths and allow-marked lines.
filter() { grep -v -e '^\./scripts/forbidden-syntax\.sh:' -e '^\./_plans/archive/' -e '\.archive\.md:' -e 'forbidden-ok' || true; }

GREP_EXCL=(--exclude-dir=node_modules --exclude-dir=target --exclude-dir=.jekyll-cache
           --exclude-dir=_site --exclude-dir=.git --exclude=poetry.lock --exclude='*.lock'
           --exclude=package-lock.json --exclude=forbidden-syntax.sh --exclude=.env)

# Patterns are built from fragments so the script never matches itself.
tn="tun""nel"
pf="port[_-]?for""ward"
mk="minikube( +-p +[^ ]+)?"
# Case-insensitive forwarding patterns.
re1i="$tn|$pf|port for""ward|forward""Ports|kubectl +pro""xy|\\bsoc""at\\b|$mk +$tn|minikube .*service .*--url"
# Case-sensitive: ssh -L forms (-l is the ssh login flag, so no -i here).
re1s="ssh .*-L |ssh +-[A-Za-z]*L|-L[0-9]"
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
        if not path or path.startswith("./_plans/archive/") or path.endswith(".archive.md"):
            continue
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                scan(path, fh.read())
        except OSError:
            pass
PYEOF
if ! command -v python3 >/dev/null 2>&1; then
    echo "forbidden-syntax: python3 not found (needed by scan 3)" >&2
    exit 1
fi

hits="$( (grep -rnIiE "${GREP_EXCL[@]}" -e "$re1i" "${targets[@]}" 2>/dev/null || true) | filter)"
[[ -n "$hits" ]] && report 'tunnel / port-forward syntax (publish a NodePort at profile creation instead)' "$hits"
hits="$( (grep -rnIE "${GREP_EXCL[@]}" -e "$re1s" "${targets[@]}" 2>/dev/null || true) | filter)"
[[ -n "$hits" ]] && report 'ssh -L style forwarding (publish a NodePort at profile creation instead)' "$hits"

hits="$( (grep -rnIE "${GREP_EXCL[@]}" -e "$re2" "${targets[@]}" 2>/dev/null || true) | filter)"
[[ -n "$hits" ]] && report 'legacy tunnel helper names' "$hits"

# Scan 3: --ports values must start with 127.0.0.1: (shell expansions ignored,
# except a bare pair inside a ${X:-a:b} default). All text files, no --include.
hits="$( (grep -rlIE "${GREP_EXCL[@]}" -e '--ports' "${targets[@]}" 2>/dev/null || true) \
    | python3 -c "$SCAN3_PY" "@files" | filter)"
[[ -n "$hits" ]] && report '--ports value without 127.0.0.1: prefix (binds 0.0.0.0)' "$hits"

# Scan 5: container runtime scope. Pattern is built from fragments so the script
# never matches itself.
pm="pod""man"
re5="$pm|rootless|cri-o|\\bcrio\\b|\\bcrun\\b|MINIKUBE_ROOTLESS|localhost:5000"
# Allowlist (grep -v -e '^<path>:' ...) is empty; a later change adds CRC appendix paths.
hits="$( (grep -rnIiE "${GREP_EXCL[@]}" -e "$re5" "${targets[@]}" 2>/dev/null || true) | filter)"
[[ -n "$hits" ]] && report 'podman/rootless/CRI-O or the retired registry name outside the CRC appendix (the minikube path is Docker Engine + containerd)' "$hits"

# Scan 6: other-OS mentions. Fragments keep the script from matching itself.
o1="mac ?""os|os ?""x|os""x|dar""win|w""sl2?|ubu""ntu|deb""ian|alp""ine|cent""os|open""suse|su""se"
o2="arch"" linux|linux ""mint|col""ima|rancher"" desktop|orb""stack|home""brew|choco""latey|win""get|power""shell|hyper""-v"
o3="rocky ?""linux|alma""linux|free""bsd|\\bpac""man\\b|\\bzyp""per\\b|win""dows-(latest|20[0-9]{2})"
re6="\\b($o1|$o2|$o3)\\b|\\.w""slconfig|%user""profile%|%app""data%|\\bbrew +(install|tap|upgrade)|\\bapt(-get)? +(install|update|upgrade)"
# Case-sensitive: "windows" in lower case is an ordinary word (time windows).
reW="\\b(Win""dows|WIN""DOWS|Mac""Book|Win1[01])\\b|Apple"" Silicon"
# Container image tags such as postgres:16-alpine are not host-OS mentions.
imgtag='[A-Za-z0-9./_-]+:[A-Za-z0-9._-]*-alp''ine[A-Za-z0-9._-]*'
msg6='other-OS mention (supported hosts are Fedora or RHEL, bare metal or VM)'
# Strip allowed tokens, then re-match what is left. Only the exact CI label
# `runs-on: ubuntu-latest` is exempt, not the rest of a runs-on: line.
os_filter() { # <extended-regex> <grep-flag-i-or-empty>; reads grep -n output on stdin
    sed -E -e 's/runs-on: ubuntu-latest([^-A-Za-z0-9_.]|$)/\1/g' -e "s#$imgtag##g" \
           -e 's/-moz-os''x-font-smoothing//g' -e 's/-apple-system//g' \
           -e "s/'Segoe UI'//g" -e 's/"Segoe UI"//g' | grep -E $2 -e "$1" || true
}
hits="$( (grep -rnIiE "${GREP_EXCL[@]}" -e "$re6" "${targets[@]}" 2>/dev/null || true) | filter | os_filter "$re6" -i)"
[[ -n "$hits" ]] && report "$msg6" "$hits"
hits="$( (grep -rnIE "${GREP_EXCL[@]}" -e "$reW" "${targets[@]}" 2>/dev/null || true) | filter | os_filter "$reW" "")"
[[ -n "$hits" ]] && report "$msg6 (case-sensitive terms)" "$hits"

nl=$'\n'   # literal newline: portable sed replacement (no GNU-only \n)
# Scan 4: slides, speaker notes, slide layouts and slide masters in every pptx.
pptx_list=()
while IFS= read -r -d '' f; do pptx_list+=("$f"); done < <(
    find . \( -name .git -o -name node_modules -o -name target -o -name _site -o -name .jekyll-cache \) -prune \
        -o -path ./_plans/archive -prune -o -type f -name '*.pptx' -print0 | sort -z)
if (( ${#pptx_list[@]} )); then
    if ! command -v unzip >/dev/null 2>&1; then
        report 'pptx scan impossible: unzip not found (install unzip; the gate cannot verify decks without it)' "$(printf '%s\n' "${pptx_list[@]}")"
    else
        for f in "${pptx_list[@]}"; do
            # Strip XML tags per paragraph so text split across <a:t> runs is rejoined.
            txt="$(unzip -p "$f" 'ppt/slides/*.xml' 'ppt/notesSlides/*.xml' \
                    'ppt/slideLayouts/*.xml' 'ppt/slideMasters/*.xml' 2>/dev/null \
                | sed -e "s#</a:p>#&\\${nl}#g" -e 's/<[^>]*>//g' || true)"
            stripped="$(printf '%s\n' "$txt" | sed -E \
                -e 's/runs-on: ubuntu-latest([^-A-Za-z0-9_.]|$)/\1/g' -e "s#$imgtag##g" \
                -e 's/-apple-system//g' -e "s/'Segoe UI'//g" -e 's/"Segoe UI"//g' || true)"
            m="$( { printf '%s\n' "$stripped" | grep -ioE ".{0,30}($re1i|$re5|$re6).{0,30}" || true
                    printf '%s\n' "$stripped" | grep -oE ".{0,30}($re1s|$reW).{0,30}" || true
                    printf '%s\n' "$txt" | python3 -c "$SCAN3_PY" - "$f" | sed -E 's/^[^:]*:[0-9]+://' || true; } \
                | sort | uniq -c | sed -E 's/^ +//' || true)"
            [[ -n "$m" ]] && report "pptx contains forbidden syntax: $f" "$m"
        done
    fi
fi

if (( fail )); then
    echo "forbidden-syntax: FAILED ($total hit lines)"
    exit 1
fi
echo "forbidden-syntax: OK"
