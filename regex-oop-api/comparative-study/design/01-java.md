# Java regex API

`java.util.regex` has four public types: `Pattern`, `Matcher`, `MatchResult` (interface), `PatternSyntaxException`. Everything else is convenience methods on `String`.

The mental model is a two-object split:

- `Pattern` is the compiled regex. Immutable and thread-safe. Compile once, share it.
- `Matcher` is the engine applied to one input. Mutable, stateful, not thread-safe. One per input (or reuse via `reset`), and it holds the current position, the last match, the region and the bounds settings.

`MatchResult` is an immutable snapshot of a match (groups and offsets). `PatternSyntaxException` is an unchecked exception thrown at compile time.

What implements `MatchResult`:

1. `Matcher` itself (`public final class Matcher implements MatchResult`). The only public implementing class.
2. `Matcher.ImmutableMatchResult`, a private static nested class: the detached snapshot behind `toMatchResult()`, the elements `results()` streams, and the return of `Scanner.match()`. User code only ever holds it as a `MatchResult`.

The interface is public, so user code can implement it too (useful for faking match results in tests).

---

## 1. Compiling: the `Pattern` class

```java
Pattern p = Pattern.compile("\\d+");
Pattern p = Pattern.compile("\\d+", Pattern.CASE_INSENSITIVE | Pattern.MULTILINE);
```

`compile` throws `PatternSyntaxException` on a bad pattern. There is no return-null path...failure is always the exception.

```java
try {
    Pattern.compile("(?<n>a)(?<n>b)");
} catch (PatternSyntaxException e) {
    // "Named capturing group <n> is already defined near index 11"
    e.getMessage();      // full message with a caret line
    e.getDescription();  // "Named capturing group <n> is already defined"
    e.getIndex();        // 11: the 0-based offset in the pattern where the parser
                         // detected the error, the '>' closing the second (?<n>,
                         // and where the caret in getMessage() points. The javadoc
                         // calls it approximate, and it is -1 when unknown.
    e.getPattern();      // the offending pattern
}
```

Introspection on a compiled pattern:

```java
p.pattern();   // the source string
p.flags();     // the int flag bitmask
p.toString();  // same as pattern()
```

`Pattern` is `Serializable`: it stores the source and flags, and recompiles on read.

### The compile flags

Pass as the second argument to `compile`, or set inline. Every flag has an inline letter except `CANON_EQ` and `LITERAL`.

| Constant                  | Inline | Meaning                                                                                     |
| ------------------------- | ------ | -------------------------------------------------------------------------------------------- |
| `CASE_INSENSITIVE`        | `(?i)` | ASCII-only case folding. Add `UNICODE_CASE` for full Unicode folding.                       |
| `UNICODE_CASE`            | `(?u)` | Makes `CASE_INSENSITIVE` fold by Unicode rules.                                             |
| `MULTILINE`               | `(?m)` | `^` and `$` match at line terminators, not only string ends.                                |
| `DOTALL`                  | `(?s)` | `.` matches line terminators too.                                                           |
| `UNIX_LINES`              | `(?d)` | Only `\n` counts as a line terminator for `.`, `^`, `$`.                                    |
| `COMMENTS`                | `(?x)` | Whitespace in the pattern is ignored and `#` starts a comment.                              |
| `LITERAL`                 | none   | The whole pattern is literal text. Only `CASE_INSENSITIVE` and `UNICODE_CASE` still apply.  |
| `UNICODE_CHARACTER_CLASS` | `(?U)` | `\w \d \s \b` and the POSIX classes use Unicode definitions. Implies `UNICODE_CASE`.        |
| `CANON_EQ`                | none   | Canonical equivalence: precomposed `é` matches decomposed `e` + combining acute. Expensive. |

The ASCII-versus-Unicode default in action:

```java
Pattern.compile("\\w").matcher("\u00e9").matches();                              // false (é is not ASCII \w)
Pattern.compile("\\w", Pattern.UNICODE_CHARACTER_CLASS).matcher("\u00e9").matches(); // true

Pattern.compile("k", Pattern.CASE_INSENSITIVE).matcher("\u212a").matches();     // false (Kelvin sign)
Pattern.compile("k", Pattern.CASE_INSENSITIVE | Pattern.UNICODE_CASE).matcher("\u212a").matches(); // true
```

---

## 2. Matching: the `Matcher` class

Get a matcher from a pattern, then choose one of three operations. The three answer different questions:

```java
Matcher m = Pattern.compile("\\d+").matcher("ab123");
m.matches();    // false: must match the ENTIRE input
m.reset();
m.lookingAt();  // false: must match at the START (need not reach the end)
m.reset();
m.find();       // true at index 2: match ANYWHERE, scanning forward
```

Repeated `find()` calls walk successive matches. `find(int start)` resets and searches from `start`. After a successful operation the match data is available until the next operation changes it.

### Groups and offsets

```java
Matcher m = Pattern.compile("(?<y>\\d{4})-(?<mo>\\d{2})").matcher("2026-09");
m.find();
m.group();        // "2026-09"  (whole match, same as group(0))
m.group(1);       // "2026"
m.group("y");     // "2026"     (named)
m.group(2);       // "09"
m.group("mo");    // "09"
m.groupCount();   // 2          (capturing groups, excluding group 0)
m.start();        // 0          start of whole match
m.end();          // 7          end (exclusive)
m.start(1);       // 0
m.end(1);         // 4
m.start("mo");    // 5
m.end("mo");      // 7
```

A group that did not participate returns `null` from `group(n)`, and `start(n)`/`end(n)` return `-1`. Never the empty string, unlike PHP.

```java
Matcher m = Pattern.compile("(a)?(b)").matcher("b");
m.find();
m.group(1);   // null   (the optional group did not match)
m.start(1);   // -1
m.group(2);   // "b"
```

`toMatchResult()` returns an immutable `MatchResult` snapshot: keep a match around while the matcher moves on.

### Named group rules

Names must match `[a-zA-Z][a-zA-Z0-9]*`. Duplicate names are a compile error. The only accepted spelling is `(?<name>...)`. The Perl `(?'name'...)` and Python `(?P<name>...)` forms are rejected.

---

## 3. Iterating all matches

The classic loop:

```java
Matcher m = Pattern.compile("\\d+").matcher("1 22 333");
while (m.find()) {
    System.out.println(m.group() + " @" + m.start());
}
```

The stream form:

```java
Pattern.compile("\\d+").matcher("1 22 333")
       .results()                       // Stream<MatchResult>
       .map(MatchResult::group)
       .toList();                       // [1, 22, 333]
```

### The zero-width-match trap

A pattern that can match the empty string matches at every position. `find()` advances by one after an empty match, so it never loops in place, but you get an empty match between every character:

```java
Matcher z = Pattern.compile("").matcher("ab");
while (z.find()) System.out.print(z.start() + ",");   // 0,1,2,
```

A custom scanning loop over such a pattern must advance past a zero-length match manually or it re-matches the same spot.

---

## 4. Replacement

```java
Pattern.compile("\\d+").matcher("a1b2").replaceAll("#");    // "a#b#"
Pattern.compile("\\d+").matcher("a1b2").replaceFirst("#");  // "a#b2"
```

In the replacement string, `$0` is the whole match, `$1`..`$n` are numbered groups and `${name}` is a named group. A literal `$` or `\` must be escaped as `\$` or `\\`.

```java
Pattern.compile("(?<y>\\d+)").matcher("42").replaceAll("[${y}]");  // "[42]"
Matcher.quoteReplacement("$5 & \\x");   // "\$5 & \\x"   escapes a string for literal insertion
```

Function-based replacement avoids replacement-string parsing entirely and computes each replacement:

```java
Pattern.compile("\\d+").matcher("1 22").replaceAll(mr -> "<" + mr.group() + ">");  // "<1> <22>"
```

### The append idiom

`replaceAll` is built on this pair. Use it for custom logic while keeping the non-matching text:

```java
Matcher m = Pattern.compile("\\d+").matcher("a1b2");
StringBuilder out = new StringBuilder();
while (m.find()) {
    m.appendReplacement(out, "#");                 // appends text-before-match + replacement
}
m.appendTail(out);                                 // appends the remainder
out.toString();                                    // "a#b#"
```

`appendReplacement` still interprets `$` and `${name}` in its replacement argument, so use `quoteReplacement` for literal text.

---

## 5. Splitting

```java
Pattern.compile(",").split("a,b,,");        // ["a", "b"]        trailing empties dropped (limit 0)
Pattern.compile(",").split("a,b,,", -1);    // ["a", "b", "", ""] negative limit keeps them
Pattern.compile(",").split("a,b,,", 2);     // ["a", "b,,"]      positive limit caps the array
```

- limit `0` (the default): trailing empty strings are removed, no cap.
- limit `< 0`: keep everything, no cap.
- limit `> 0`: at most `limit` elements, the last holds the rest.

Zero-width split: no leading empty string for a match at the very start.

```java
Pattern.compile("").split("abc");        // ["a", "b", "c"]
Pattern.compile("(?<=.)").split("abc");  // ["a", "b", "c"]
```

`splitAsStream(CharSequence)` returns a lazy `Stream<String>`.

---

## 6. Regions and bounds

A region restricts the matcher to a sub-range without copying the string:

```java
Matcher m = Pattern.compile("...").matcher(input);
m.region(start, end);
m.regionStart(); m.regionEnd();
```

Transparent bounds decide whether lookaround and boundaries can see text outside the region. Default is opaque.

```java
Matcher m = Pattern.compile("(?<=a)b").matcher("ab");
m.region(1, 2); m.find();                    // false: the lookbehind can't see the 'a' outside
m.region(1, 2); m.useTransparentBounds(true);
m.find();                                    // true: now it can
```

Anchoring bounds decide whether `^` and `$` match at the region edges. Default is on.

```java
Matcher m = Pattern.compile("^b$").matcher("ab");
m.region(1, 2); m.find();                     // true: region edges act as ^ and $
m.region(1, 2); m.useAnchoringBounds(false);
m.find();                                     // false
```

---

## 7. Streaming and incremental matching

No true partial-match mode like PCRE's `PARTIAL_HARD`. Two hints are the closest thing when feeding data in chunks:

- `hitEnd()`: the engine reached the end of input during the last attempt, so more input might change the outcome.
- `requireEnd()`: more input could turn the current match into a non-match (a `$` held only because input ended).

```java
Matcher m = Pattern.compile("\\d{4}").matcher("202");
m.matches();      // false
m.hitEnd();       // true: one more digit could still make a match
```

Reusing a matcher:

```java
m.reset();               // rewind to position 0, same input
m.reset(newInput);       // rewind and swap input
m.usePattern(newPattern);// swap the pattern, keep the position (append-style scanners)
```

---

## 8. Predicates and streams

```java
Pattern.compile("\\d+").asPredicate().test("ab3");        // true  (find semantics: contains a match)
Pattern.compile("\\d+").asMatchPredicate().test("ab3");   // false (matches semantics: whole string)
Pattern.compile("\\d+").matcher(s).results();             // Stream<MatchResult>
Pattern.compile(",").splitAsStream("a,b,c");              // Stream<String>
```

The idiomatic stream filter:

```java
list.stream().filter(Pattern.compile("^\\d+$").asMatchPredicate()).toList();
```

---

## 9. The pattern syntax Java supports

Perl-like with some gaps. The full construct list:

### Literals and escapes
- Metacharacters: `\ . [ ] { } ( ) * + ? ^ $ |`. Anything else is a literal.
- `\\` backslash, `\t \n \r \f \a \e` controls, `\cX` control char, `\0nn` octal, `\xhh` and `\x{h...}` hex, `\uhhhh` UTF-16 code unit. No `\N{...}` named codepoints.
- `\Q...\E` quotes a run as literal. `Pattern.quote(s)` wraps a whole string this way.

### Character classes
- `[abc]`, `[^abc]`, ranges `[a-z]`, unions `[a-d[m-p]]`, intersections `[a-z&&[^bc]]`, nested negation. `&&` is the class intersection operator.
- Predefined: `.` (any but line terminators, all with `DOTALL`), `\d \D`, `\w \W`, `\s \S`, `\h \H` horizontal whitespace, `\v \V` vertical whitespace.
- `\R` any line-break sequence, `\r\n` as one:

```java
Pattern.compile("\\R").matcher("\r\n").matches();  // true
```

### POSIX and Unicode properties
- POSIX (ASCII by default, Unicode under `UNICODE_CHARACTER_CLASS`): `\p{Alpha} \p{Digit} \p{Alnum} \p{Punct} \p{Space} \p{Upper} \p{Lower} \p{Blank} \p{Cntrl} \p{XDigit} \p{Graph} \p{Print} \p{ASCII}`.
- Unicode general category: `\p{L}`, `\p{Lu}`, `\p{gc=Lu}`, `\p{IsAlphabetic}`, `\p{IsL}`.
- Unicode scripts: `\p{IsLatin}`, `\p{script=Greek}`, `\p{sc=Greek}`.
- Unicode blocks: `\p{InGreek}`, `\p{block=Greek}`, `\p{blk=Greek}`.
- Java-specific, backed by `java.lang.Character.isX`: `\p{javaLowerCase}`, `\p{javaUpperCase}`, `\p{javaWhitespace}`, `\p{javaMirrored}` and the rest of the family.

```java
Pattern.compile("\\p{javaLowerCase}").matcher("a").matches();  // true
Pattern.compile("\\p{IsLatin}").matcher("a").matches();        // true
Pattern.compile("\\p{sc=Greek}").matcher("\u03b1").matches();  // true
```

### Quantifiers
Greedy `X? X* X+ X{n} X{n,} X{n,m}`. Lazy: append `?` (`X*?`). Possessive: append `+` (`X*+`), never gives back.

```java
Pattern.compile("a+a").matcher("aaa").matches();   // true  (greedy gives back)
Pattern.compile("a++a").matcher("aaa").matches();  // false (possessive keeps all a's)
```

### Groups
- Capturing `(...)`, non-capturing `(?:...)`, named `(?<name>...)`.
- Atomic `(?>...)`: no backtracking into it.
- Flag-scoped `(?i:...)`, inline toggles `(?i)`, `(?-i)`, `(?idmsuxU)`.

```java
Pattern.compile("(?>a+)a").matcher("aaa").matches();  // false (atomic, same effect as a++)
```

### Backreferences
Numbered `\1`..`\9`, named `\k<name>`.

```java
Pattern.compile("(\\w)\\1").matcher("aa").matches();       // true
Pattern.compile("(?<c>\\w)\\k<c>").matcher("aa").matches(); // true
```

### Lookaround
Lookahead `(?=...)` `(?!...)`, lookbehind `(?<=...)` `(?<!...)`. Lookbehind allows bounded variable length, not unbounded quantifiers.

### Boundaries and anchors
- `^ $` (line-aware under `MULTILINE`), `\b \B` word boundary, `\A` start of input, `\z` very end, `\Z` end before a final line terminator, `\G` end of the previous match.
- `\b{g}` grapheme cluster boundary: a base character and its combining marks stay together.

```java
"a\u0301b".split("\\b{g}");     // ["á", "b"]  (a + combining acute is one grapheme)
Pattern.compile("abc\\Z").matcher("abc\n").find();  // true  (\Z allows the trailing newline)
Pattern.compile("abc\\z").matcher("abc\n").find();  // false (\z is the very end)
```

---

## 10. What Java does NOT have (versus PCRE)

This bounds what a port can copy:

- No recursion or subroutine calls (`(?R)`, `(?1)`, `(?&name)`).
- No conditionals (`(?(1)yes|no)`).
- No `\K`.
- No branch reset `(?|...)`.
- No DEFINE blocks.
- No script runs, no callouts, no `\C`.
- No inline comment `(?#...)`. Comments only via `COMMENTS`/`(?x)`.
- Named groups in the `(?<name>)` spelling only.
- No `\N{U+xxxx}` or `\N{NAME}`.
- No built-in match timeout (workaround below).

Shared with PCRE: atomic groups, possessive quantifiers, bounded lookbehind, named groups, Unicode properties.

---

## 11. Gotchas, tricks, workarounds

### The `String` convenience methods recompile every call
`String.matches`, `String.split`, `String.replaceAll`, `String.replaceFirst` compile a fresh `Pattern` per invocation. In a loop, compile once and reuse.

```java
"ab123".matches("\\d+");        // false: matches() is a FULL match
"ab123".matches(".*\\d+.*");    // true
```

`String.matches` is a full-string match, not a search. The name reads like a search and it is not.

### Reusing a `Matcher` across threads is a bug
`Pattern` is meant to be shared (a `static final` field). `Matcher` is not. One matcher per thread: per call, or a `ThreadLocal<Matcher>` reset per use.

### `$` and `\` in replacement strings
A dollar starts a group reference and a backslash escapes. Literal user text must go through `Matcher.quoteReplacement`, or a stray `$` throws `IllegalArgumentException` at replace time.

### Zero-width matches in custom loops
See section 3. Advance manually past zero-length matches.

### `split` and trailing empties
Dropped by default. Pass a negative limit to keep them. Fixed-column data is where this shows up.

### Catastrophic backtracking and ReDoS
A backtracking engine, so `(a+)+$` on a long non-matching input can hang. Mitigations, in order of preference:

1. Rewrite to avoid nested quantifiers, or make inner quantifiers possessive or atomic: `(?>a+)+` or `a++`.
2. There is no built-in timeout. The known workaround is an interruptible `CharSequence`: `charAt` checks the thread's interrupt flag and throws, and a watchdog interrupts the matching thread.

```java
// Abort a runaway match via Thread.interrupt().
final class InterruptibleCharSequence implements CharSequence {
    private final CharSequence inner;
    InterruptibleCharSequence(CharSequence s) { this.inner = s; }
    public char charAt(int i) {
        if (Thread.currentThread().isInterrupted())
            throw new RuntimeException("regex interrupted");
        return inner.charAt(i);
    }
    public int length() { return inner.length(); }
    public CharSequence subSequence(int a, int b) {
        return new InterruptibleCharSequence(inner.subSequence(a, b));
    }
    public String toString() { return inner.toString(); }
}
// Matcher calls charAt as it scans, so an interrupt breaks the loop.
Matcher m = pattern.matcher(new InterruptibleCharSequence(userInput));
```

### `CANON_EQ` is a correctness tool with a cost
Makes precomposed `é` and `e` + combining acute compare equal. Off by default and noticeably slower, so reach for it only when normalizing the input is not an option.

### ASCII defaults on the shorthand classes
`\w \d \s \b` and the POSIX classes are ASCII-only unless `UNICODE_CHARACTER_CLASS` is set. Code that "works" on English data fails on accented text. Decide deliberately per pattern.

### Anchors and `MULTILINE`
`^` and `$` mean start/end of input by default. Line-by-line anchoring needs `MULTILINE`. `$` matches before a final line terminator (`"abc\n"` matches `abc$`), use `\z` for strictly the end.

### `find()` after `matches()`
Match operations share state. Call `reset()` between different operations on one matcher, or the position carries over.
