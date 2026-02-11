#!/usr/bin/env bash
# spectra-verify-wiring.sh — Automated wiring verification for SPECTRA projects
# Reads .spectra/verify.yaml and enforces rules. Exit 0=pass, 1=violations found.
# Usage: spectra-verify-wiring.sh [PROJECT_ROOT] [--verbose] [--fix-hints] [--self-test]
set -euo pipefail

[[ -t 1 ]] && { RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'; } \
            || { RED=''; GREEN=''; YELLOW=''; NC=''; }

VERBOSE=false; FIX_HINTS=false; PROJECT_ROOT="."
for arg in "$@"; do
    case "$arg" in
        --verbose)   VERBOSE=true ;;
        --fix-hints) FIX_HINTS=true ;;
        --self-test) SELF_TEST=true ;;
        --help|-h)   echo "Usage: spectra-verify-wiring.sh [ROOT] [--verbose] [--fix-hints] [--self-test]"; exit 0 ;;
        --*) echo "Unknown: $arg"; exit 1 ;;
        *)   PROJECT_ROOT="$arg" ;;
    esac
done

# ── Self-test ──
if [[ "${SELF_TEST:-}" == true ]]; then
    T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
    mkdir -p "$T/src" "$T/tests" "$T/.spectra"
    cat > "$T/src/app.py" <<'F'
from src.handler import process
def main(): return process()
F
    cat > "$T/src/handler.py" <<'F'
from src.helper import compute
def process(): return compute()
F
    echo 'def compute(): return 42' > "$T/src/helper.py"
    echo 'def orphan_function(): return "never called"' > "$T/src/dead_module.py"
    cat > "$T/tests/test_dead.py" <<'F'
from src.dead_module import orphan_function
def test_orphan(): assert orphan_function()
F
    cat > "$T/.spectra/verify.yaml" <<'F'
project:
  source_dirs: ["src/"]
  test_dirs: ["tests/"]
  entry_points: ["src/app.py"]
  language: python
rules:
  wiring:
    enabled: true
    ignore_patterns: ["_*", "test_*", "__*"]
  framework_checks: []
  constants: []
  write_guard:
    enabled: false
F
    set +e; OUT=$("$0" "$T" --verbose 2>&1); EC=$?; set -e
    PASS=0; FAIL=0
    check() { if eval "$1"; then printf "${GREEN}[self-test] PASS: $2${NC}\n"; PASS=$((PASS+1))
              else printf "${RED}[self-test] FAIL: $2${NC}\n"; FAIL=$((FAIL+1)); echo "$OUT"; fi; }
    check 'echo "$OUT" | grep -q "PASS.*compute"' "helper.py::compute detected as wired"
    check 'echo "$OUT" | grep -q "FAIL.*orphan_function"' "dead_module.py::orphan_function detected as dead"
    check '[[ "$EC" -eq 1 ]]' "exit code is 1 (violations found)"
    [[ $FAIL -eq 0 ]] && { printf "\n${GREEN}[self-test] ALL $PASS ASSERTIONS PASSED${NC}\n"; exit 0; } || exit 1
fi

# ── Config ──
CFG="$PROJECT_ROOT/.spectra/verify.yaml"
[[ -f "$CFG" ]] || { echo "[spectra-verify] No verify.yaml found, skipping"; exit 0; }
V=0  # violation counter

report() { case "$1" in
    PASS) printf "  ${GREEN}PASS${NC}  %s\n" "$2" ;;
    FAIL) printf "  ${RED}FAIL${NC}  %s\n" "$2"; V=$((V+1)) ;;
    SKIP) printf "  ${YELLOW}SKIP${NC}  %s\n" "$2" ;;
esac; }

# YAML helpers — yq preferred, awk fallback for nested paths
_yaml_nav() {
    # Navigate dotted path in YAML, print the raw value after the leaf key's colon
    local path="$1" file="$2"
    awk -v path="$path" '
    BEGIN { n=split(path,keys,"."); depth=1; for(i=1;i<=n;i++) exp_indent[i]=-1 }
    /^[[:space:]]*#/||/^[[:space:]]*$/ { next }
    { match($0,/^[[:space:]]*/); ind=RLENGTH
      while(depth>1 && ind<=exp_indent[depth-1]) depth--
      re="^[[:space:]]*"keys[depth]"[[:space:]]*:"
      if($0~re){
        if(depth==n){ sub(/^[[:space:]]*[^:]+:[[:space:]]*/,"",$0); print $0; exit }
        else{ exp_indent[depth]=ind; depth++ }
      }
    }' "$file" 2>/dev/null
}
yv() { # Extract scalar value at dotted path
    if command -v yq >/dev/null 2>&1; then yq -r ".$1 // \"\"" "$2" 2>/dev/null
    else _yaml_nav "$1" "$2" | sed 's/^["'"'"']//;s/["'"'"']$//' ; fi; }
yl() { # Extract list value at dotted path as newline-separated items
    if command -v yq >/dev/null 2>&1; then yq -r ".$1 // [] | .[]" "$2" 2>/dev/null || true
    else _yaml_nav "$1" "$2" | tr -d '[]"'"'" | tr ',' '\n' | sed 's/^\s*//;s/\s*$//' | { grep -v '^$' || true; }; fi; }

SRC_DIRS=$(yl "project.source_dirs" "$CFG")
TST_DIRS=$(yl "project.test_dirs" "$CFG")
LANG=$(yv "project.language" "$CFG")
WIRING=$(yv "rules.wiring.enabled" "$CFG")
IGNORES=$(yl "rules.wiring.ignore_patterns" "$CFG")

case "$LANG" in
    python)     FDEF='^[[:space:]]*(def|class)[[:space:]]+[a-zA-Z]'; EXT="py"
                fname_extract() { sed -n 's/.*\(def\|class\)[[:space:]]*\([a-zA-Z_][a-zA-Z0-9_]*\).*/\2/p'; } ;;
    typescript) FDEF='export[[:space:]]+(async[[:space:]]+)?(function|const|let)[[:space:]]+[a-zA-Z]'; EXT="ts"
                fname_extract() { sed -n 's/.*\(function\|const\|let\)[[:space:]]*\([a-zA-Z_][a-zA-Z0-9_]*\).*/\2/p'; } ;;
    javascript) FDEF='export[[:space:]]+(async[[:space:]]+)?(function|const|let)[[:space:]]+[a-zA-Z]'; EXT="js"
                fname_extract() { sed -n 's/.*\(function\|const\|let\)[[:space:]]*\([a-zA-Z_][a-zA-Z0-9_]*\).*/\2/p'; } ;;
    go)         FDEF='^func[[:space:]]+[A-Z]'; EXT="go"
                fname_extract() { sed -n 's/.*func[[:space:]]*\([A-Z][a-zA-Z0-9_]*\).*/\1/p'; } ;;
    rust)       FDEF='^[[:space:]]*pub[[:space:]]+(fn|struct|enum)[[:space:]]+[a-zA-Z]'; EXT="rs"
                fname_extract() { sed -n 's/.*\(fn\|struct\|enum\)[[:space:]]*\([a-zA-Z_][a-zA-Z0-9_]*\).*/\2/p'; } ;;
    *)          FDEF=''; EXT=""
                fname_extract() { cat; } ;;
esac

# Build test-dir exclusion flags
TEXCL=""
while IFS= read -r td; do [[ -n "$td" ]] && TEXCL="$TEXCL --exclude-dir=${td%/}"; done <<< "$TST_DIRS"

# ── Section 1: Wiring ──
if [[ "$WIRING" == "true" && -n "$FDEF" && -n "$SRC_DIRS" ]]; then
    echo "[spectra-verify] Section 1: Wiring check"
    while IFS= read -r sd; do
        [[ -z "$sd" ]] && continue; sp="$PROJECT_ROOT/${sd%/}"; [[ -d "$sp" ]] || continue
        while IFS= read -r sf; do
            [[ -z "$sf" ]] && continue; rf="${sf#$PROJECT_ROOT/}"
            while IFS= read -r ml; do
                [[ -z "$ml" ]] && continue
                fn=$(echo "$ml" | fname_extract); [[ -z "$fn" ]] && continue
                skip=false; while IFS= read -r pat; do
                    [[ -z "$pat" ]] && continue; [[ "$fn" == ${pat} ]] && skip=true
                done <<< "$IGNORES"; [[ "$skip" == true ]] && continue
                hits=0; while IFS= read -r s2; do
                    [[ -z "$s2" ]] && continue; s2p="$PROJECT_ROOT/${s2%/}"; [[ -d "$s2p" ]] || continue
                    # shellcheck disable=SC2086
                    c=$( (grep -rn --include="*.${EXT}" $TEXCL "$fn" "$s2p" 2>/dev/null \
                        | grep -v "^${sf}:" | grep -v "def ${fn}" | grep -v "class ${fn}" \
                        | grep -v '^\s*#' || true) | wc -l); c=$(echo "$c" | tr -d ' '); c=${c:-0}
                    hits=$((hits+c))
                done <<< "$SRC_DIRS"
                if [[ $hits -gt 0 ]]; then report "PASS" "${rf}::${fn} (${hits} callsite(s))"
                else report "FAIL" "${rf}::${fn} — no callsites in source (dead code)"
                    [[ "$FIX_HINTS" == true ]] && echo "         Hint: wire ${fn}() into an entry point"
                fi
            done < <(grep -nE "$FDEF" "$sf" 2>/dev/null | head -50)
        done < <(find "$sp" -name "*.${EXT}" -type f 2>/dev/null | sort)
    done <<< "$SRC_DIRS"; echo ""
fi

# ── Section 2: Framework checks ──
parse_fw() { local n="" p="" s="" m="" ps=""
    while IFS= read -r l; do
        if echo "$l" | grep -qE '^\s+- name:'; then
            [[ -n "$n" && -n "$p" ]] && echo "${n}|${p}|${s:-error}|${m:-}|${ps}"
            n=$(echo "$l" | sed 's/.*name:\s*//;s/^["'"'"']//;s/["'"'"']$//'); p="" s="" m="" ps=""
        elif echo "$l" | grep -qE '^\s+pattern:'; then p=$(echo "$l" | sed "s/.*pattern:\s*//;s/^[\"']//;s/[\"']$//")
        elif echo "$l" | grep -qE '^\s+severity:'; then s=$(echo "$l" | sed "s/.*severity:\s*//;s/^[\"']//;s/[\"']$//")
        elif echo "$l" | grep -qE '^\s+message:'; then m=$(echo "$l" | sed "s/.*message:\s*//;s/^[\"']//;s/[\"']$//")
        elif echo "$l" | grep -qE '^\s+paths:'; then ps=$(echo "$l" | sed 's/.*paths:\s*//' | tr -d '[]"'"'" | tr ',' ' ')
        fi
    done < <(awk '
        /^[[:space:]]*framework_checks:/ { found=1; match($0,/^[[:space:]]*/); base=RLENGTH; next }
        found { match($0,/^[[:space:]]*/); ind=RLENGTH
            if(ind<=base && $0~/[a-z]/) exit
            print
        }' "$1")
    [[ -n "$n" && -n "$p" ]] && echo "${n}|${p}|${s:-error}|${m:-}|${ps}"; }

FW=$(parse_fw "$CFG")
if [[ -n "$FW" ]]; then
    echo "[spectra-verify] Section 2: Framework checks"
    while IFS='|' read -r name pat sev msg paths; do
        [[ -z "$name" ]] && continue; sp=""
        if [[ -n "$paths" ]]; then for p in $paths; do t="$PROJECT_ROOT/${p%/}"
            { [[ -d "$t" ]] || [[ -f "$t" ]]; } && sp="$sp $t"; done
        else while IFS= read -r sd; do [[ -n "$sd" ]] && { t="$PROJECT_ROOT/${sd%/}"; [[ -d "$t" ]] && sp="$sp $t"; }
            done <<< "$SRC_DIRS"; fi
        [[ -z "$sp" ]] && continue
        # shellcheck disable=SC2086
        h=$(grep -rnE "$pat" $sp 2>/dev/null || true); hc=0; [[ -n "$h" ]] && hc=$(echo "$h" | wc -l)
        if [[ $hc -gt 0 ]]; then report "FAIL" "[${name}] ${msg} (${hc} match(es))"
            [[ "$VERBOSE" == true ]] && echo "$h" | head -5 | sed 's/^/         /'
        else report "PASS" "[${name}] clean"; fi
    done <<< "$FW"; echo ""
fi

# ── Section 3: Write guard ──
if [[ "$(yv 'rules.write_guard.enabled' "$CFG")" == "true" ]]; then
    echo "[spectra-verify] Section 3: Write guard"
    WP=$(yv "rules.write_guard.raw_pattern" "$CFG"); WA=$(yv "rules.write_guard.abstraction" "$CFG")
    WM=$(yv "rules.write_guard.message" "$CFG"); WX=$(yl "rules.write_guard.exclude_files" "$CFG")
    XA=""; while IFS= read -r ef; do [[ -n "$ef" ]] && XA="$XA --exclude=$ef"; done <<< "$WX"
    if [[ -n "$WP" ]]; then while IFS= read -r sd; do
        [[ -z "$sd" ]] && continue; sp="$PROJECT_ROOT/${sd%/}"; [[ -d "$sp" ]] || continue
        # shellcheck disable=SC2086
        raw=$(grep -rnE "$WP" $XA "$sp" 2>/dev/null || true)
        [[ -n "$raw" && -n "$WA" ]] && raw=$(echo "$raw" | grep -v "$WA" || true)
        rc=0; [[ -n "$raw" ]] && rc=$(echo "$raw" | wc -l)
        if [[ $rc -gt 0 ]]; then report "FAIL" "${WM:-Direct write} ($rc violation(s))"
            [[ "$VERBOSE" == true ]] && echo "$raw" | head -5 | sed 's/^/         /'
        else report "PASS" "Write guard clean in ${sd}"; fi
    done <<< "$SRC_DIRS"; fi; echo ""
fi

# ── Section 4: Constants ──
parse_const() { local f="" p="" m=""
    while IFS= read -r l; do
        if echo "$l" | grep -qE '^\s+- file:'; then
            [[ -n "$f" && -n "$p" ]] && echo "${f}|${p}|${m:-constant check}"
            f=$(echo "$l" | sed "s/.*file:\s*//;s/^[\"']//;s/[\"']$//"); p="" m=""
        elif echo "$l" | grep -qE '^\s+pattern:'; then p=$(echo "$l" | sed "s/.*pattern:\s*//;s/^[\"']//;s/[\"']$//")
        elif echo "$l" | grep -qE '^\s+message:'; then m=$(echo "$l" | sed "s/.*message:\s*//;s/^[\"']//;s/[\"']$//")
        fi
    done < <(awk '
        /^[[:space:]]*constants:/ { found=1; match($0,/^[[:space:]]*/); base=RLENGTH; next }
        found { match($0,/^[[:space:]]*/); ind=RLENGTH
            if(ind<=base && $0~/[a-z]/) exit; print
        }' "$1" | head -50)
    [[ -n "$f" && -n "$p" ]] && echo "${f}|${p}|${m:-constant check}"; }

CS=$(parse_const "$CFG")
if [[ -n "$CS" ]]; then
    echo "[spectra-verify] Section 4: Constants check"
    while IFS='|' read -r file pat msg; do
        [[ -z "$file" ]] && continue; fp="$PROJECT_ROOT/$file"
        [[ -f "$fp" ]] || { report "FAIL" "[${file}] file not found"; continue; }
        grep -qE "$pat" "$fp" 2>/dev/null && report "PASS" "[${file}] ${msg}" \
            || report "FAIL" "[${file}] ${msg} — pattern not found: ${pat}"
    done <<< "$CS"; echo ""
fi

# ── Section 5: Plan assertions ──
PF="$PROJECT_ROOT/.spectra/plan.md"
if [[ -f "$PF" ]]; then
    AS=$(grep -E '^\s+- (GREP|CALLSITE|COUNT) ' "$PF" 2>/dev/null || true)
    if [[ -n "$AS" ]]; then
        echo "[spectra-verify] Section 5: Plan assertions"
        while IFS= read -r a; do
            [[ -z "$a" ]] && continue; a=$(echo "$a" | sed 's/^\s*- //')
            TY=$(echo "$a" | awk '{print $1}')
            case "$TY" in
                GREP) af=$(echo "$a" | awk '{print $2}'); ap=$(echo "$a" | sed 's/.*"\(.*\)".*/\1/')
                    ae=$(echo "$a" | awk '{print $NF}'); fp="$PROJECT_ROOT/$af"
                    [[ -f "$fp" ]] || { report "FAIL" "GREP ${af} — file not found"; continue; }
                    fc=$(grep -cE "$ap" "$fp" 2>/dev/null || echo 0)
                    if [[ "$ae" == "EXISTS" ]]; then [[ $fc -gt 0 ]] && report "PASS" "GREP ${af} \"${ap}\" EXISTS" \
                        || report "FAIL" "GREP ${af} — \"${ap}\" not found"
                    elif [[ "$ae" == "NOT_EXISTS" ]]; then [[ $fc -eq 0 ]] && report "PASS" "GREP ${af} \"${ap}\" NOT_EXISTS" \
                        || report "FAIL" "GREP ${af} — \"${ap}\" should not exist"; fi ;;
                CALLSITE) fn=$(echo "$a" | awk '{print $2}'); ed=$(echo "$a" | awk '{print $4}')
                    cs=$(grep -rn "$fn" "$PROJECT_ROOT" --include="*.${EXT:-py}" --exclude-dir="${ed%/}" 2>/dev/null \
                        | grep -v "def ${fn}" | grep -v "class ${fn}" || true)
                    cc=0; [[ -n "$cs" ]] && cc=$(echo "$cs" | wc -l)
                    [[ $cc -gt 0 ]] && report "PASS" "CALLSITE ${fn} (${cc} outside ${ed})" \
                        || report "FAIL" "CALLSITE ${fn} — only in ${ed}" ;;
                COUNT) af=$(echo "$a" | awk '{print $2}'); ap=$(echo "$a" | sed 's/.*"\(.*\)".*/\1/')
                    am=$(echo "$a" | awk '{print $NF}'); fp="$PROJECT_ROOT/$af"
                    [[ -f "$fp" ]] || { report "FAIL" "COUNT ${af} — file not found"; continue; }
                    ac=$(grep -cE "$ap" "$fp" 2>/dev/null || echo 0)
                    [[ $ac -ge $am ]] && report "PASS" "COUNT ${af} \"${ap}\" >= ${am} (${ac})" \
                        || report "FAIL" "COUNT ${af} \"${ap}\" expected >= ${am}, got ${ac}" ;;
                *) report "SKIP" "Unknown assertion: ${TY}" ;;
            esac
        done <<< "$AS"; echo ""
    fi
fi

# ── Summary ──
echo "─────────────────────────────────────────"
if [[ $V -gt 0 ]]; then printf "${RED}[spectra-verify] FAIL: ${V} violation(s) found${NC}\n"; exit 1
else printf "${GREEN}[spectra-verify] PASS: all wiring checks clean${NC}\n"; exit 0; fi
