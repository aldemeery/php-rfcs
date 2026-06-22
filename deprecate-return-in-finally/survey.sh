#!/usr/bin/env bash
#
# Survey: count `return` inside a `finally` block across a corpus of packages,
# using the PATCHED php as the detector (the compile-time deprecation itself).
# This is exact, not an approximation: it measures precisely what would ship.
#
# Usage:
#   PHP=/path/to/patched/php ./survey.sh [CORPUS_ROOT]
#
#   CORPUS_ROOT defaults to ./popular-package-analysis
#   It must contain zipballs/<vendor>/<pkg>.zip (nikic/popular-package-analysis layout).
#   sources/ is created (php-only extraction) if absent.
#
set -uo pipefail

PHP="${PHP:-php}"
ROOT="${1:-./popular-package-analysis}"
SRC="$ROOT/sources"
NP="$(nproc)"
export PHP

# --- 0. verify the detector actually emits the deprecation -------------------
"$PHP" -v >/dev/null 2>&1 || { echo "ERROR: php not runnable at PHP=$PHP"; exit 1; }
printf '<?php function _p(){ try {} finally { return 1; } }\n' > /tmp/_dep_probe.php
if ! "$PHP" -n -l /tmp/_dep_probe.php 2>&1 | grep -q "Returning from a finally block"; then
    echo "ERROR: this php does NOT emit the finally deprecation."
    echo "       Build the patched php-src first, or point PHP= at it."
    exit 1
fi
echo "detector OK: patched php emits the finally-return deprecation"

# --- 1. extract php-only (only if sources/ is missing) -----------------------
if [ ! -d "$SRC" ]; then
    echo "[extract] sources/ absent - extracting php-only from zipballs ..."
    cd "$ROOT" || exit 1
    find zipballs -mindepth 2 -name '*.zip' -type f -print0 \
    | xargs -0 -P "$NP" -I{} bash -c '
        zip="$1"; tgt="sources/${zip#zipballs/}"; tgt="${tgt%.zip}"
        mkdir -p "$tgt"
        unzip -o -qq "$zip" "*.php" -d "$tgt" 2>/dev/null
        exit 0
      ' _ {}
    echo "[extract] done: $(find sources -name '*.php' | wc -l) php files"
fi

# --- 2. prefilter: files containing the `finally` token (case-insensitive) ---
# PHP keywords are case-insensitive, so we must grep -i or we miss FINALLY/Finally.
# A real finally block requires the token, so this candidate set is a strict superset.
echo "[1/3] finding candidate files (contain 'finally') ..."
grep -rlIiw finally "$SRC" --include='*.php' > /tmp/_cand.txt 2>/dev/null
echo "      candidates: $(wc -l < /tmp/_cand.txt)"

# --- 3. lint candidates with the patched php ---------------------------------
# NOTE: `php -l` exits 255 on a parse error, and xargs ABORTS the whole run on 255.
# So we wrap in a bash loop that swallows the exit code (exit 0).
echo "[2/3] linting candidates (patched php -n -l) ..."
tr '\n' '\0' < /tmp/_cand.txt \
| xargs -0 -P "$NP" -n 40 bash -c 'for f in "$@"; do "$PHP" -n -l "$f" 2>&1; done; exit 0' _ \
> /tmp/_lint.log 2>&1

# --- 4. collect + report -----------------------------------------------------
echo "[3/3] collecting hits ..."
grep "Returning from a finally block" /tmp/_lint.log | sort -u > "$ROOT/finally_hits.txt"

echo "==================== RESULT ===================="
echo "candidate files (contain 'finally') : $(wc -l < /tmp/_cand.txt)"
echo "parse errors among candidates       : $(grep -c 'Parse error' /tmp/_lint.log)  (blind spots)"
echo "FINALLY-RETURN HIT LINES            : $(wc -l < "$ROOT/finally_hits.txt")"
echo "distinct files                      : $(sed 's/ on line [0-9]*$//' "$ROOT/finally_hits.txt" | sort -u | wc -l)"
echo "distinct packages                   : $(grep -oP 'sources/\K[^/]+/[^/]+' "$ROOT/finally_hits.txt" | sort -u | wc -l)"
echo "hits written to                     : $ROOT/finally_hits.txt"
echo "================================================"
sed 's#.*deprecated in ##' "$ROOT/finally_hits.txt"
