| # | Capability | What it is | |
|---|---|---|---|
| 01 | Partial matching | A third match outcome that says "could match with more input". Type-ahead validation and streaming. | [demo](01-partial-matching.pcre2test) |
| 02 | DFA matching | A second engine. It reports all matches at a point (longest first) and it can suspend and resume across input chunks. No backtracking. | [demo](02-dfa-matching.pcre2test) |
| 03 | Callouts | `(?Cn)` calls user code mid-match. PHP compiles the syntax but no handler can ever be attached. Also covers callout enumeration and auto callouts. | [demo](03-callouts.pcre2test) |
| 04 | Native substitution | `pcre2_substitute()` templates. `${name}` references, case forcing, `${n:-default}` fallbacks and the unset-empty and replacement-only modes. | [demo](04-substitution.pcre2test) |
| 05 | Match-time options | Per-call `NOTBOL`/`NOTEOL`/`NOTEMPTY(_ATSTART)`/`ANCHORED`/`ENDANCHORED`. Anchors that tell the truth about buffer windows, plus empty-match control. | [demo](05-match-time-options.pcre2test) |
| 06 | Per-call resource limits | Match/depth/heap/offset budgets per call instead of two process-wide INIs, plus `find_limits` discovery of what a match actually costs. | [demo](06-resource-limits.pcre2test) |
| 07 | Pattern introspection | `pcre2_pattern_info()` reports group count, name table, max lookbehind, starting units and minimum subject length. | [demo](07-pattern-introspection.pcre2test) |
| 08 | Pattern serialization | Compile once and save the bytes, then load and match elsewhere without recompiling. PHP's cache is per-process and invisible. | [demo](08-serialization.pcre2test) |
| 09 | JIT stack control | Size the JIT match stack per call. PHP hardcodes 32/192 KiB and reports only `PREG_JIT_STACKLIMIT_ERROR`. | [demo](09-jit-stack-control.pcre2test) |
| 10 | Extended character classes | `(?[ \p{L} & \p{ASCII} ])` brings real set algebra inside classes. | [demo](10-extended-character-classes.pcre2test) |
| 11 | Scan substring | `(*scs:(ref) pat)` asserts a sub-pattern against a captured group's content, with its own anchors. | [demo](11-scan-substring.pcre2test) |
| 12 | ECMAScript-style escapes | JavaScript-convention `\uHHHH` and `\u{...}` escapes via `ALT_BSUX`/`EXTRA_ALT_BSUX`. Native PCRE2 rejects them and PHP cannot enable the option. | [demo](12-alt-bsux-escapes.pcre2test) |
| 13 | API-only compile options | `LITERAL` (whole pattern as text), `MATCH_UNSET_BACKREF` (JS unset-backref semantics), `FIRSTLINE` and more. No modifier letter and no directive can reach these. | [demo](13-compile-options-only.pcre2test) |
| 14 | Extra compile options | `EXTRA_MATCH_WORD` and `EXTRA_MATCH_LINE` (grep -w and -x as engine options), `EXTRA_BAD_ESCAPE_IS_LITERAL` (lenient escapes) and `EXTRA_ALLOW_LOOKAROUND_BSK` (\K in lookarounds again). | [demo](14-extra-compile-options.pcre2test) |
| 15 | Pattern conversion | `pcre2_pattern_convert()` translates shell globs and POSIX dialects into PCRE2 patterns. | [demo](15-pattern-conversion.pcre2test) |
| 16 | Subroutine calls returning captures | `(?&name(<group>,...))` is a subroutine call that exports the listed captures back to the calling context. | [demo](16-subroutine-call-captures.pcre2test) |
