# C# regex API

The namespace is `System.Text.RegularExpressions`.
The public surface is one engine class plus a result-object tree:
- `Regex`
- `Match`
- `MatchCollection`
- `Group`
- `GroupCollection`
- `Capture`
- `CaptureCollection`
- `RegexOptions` (flags enum)
- `MatchEvaluator` (delegate)
- `RegexParseException`
- `RegexMatchTimeoutException`
- `GeneratedRegexAttribute`
- `ValueMatch`
- `Regex.ValueMatchEnumerator`
- `Regex.ValueSplitEnumerator`

The mental model is a one-object engine with an immutable result tree:

- `Regex` is the compiled pattern. Immutable and thread-safe ("Regex objects can be created on any thread and shared between threads"). There is no Java-style `Matcher`: no mutable engine object ever reaches user code.
- `Match` is an immutable snapshot of one match. It doubles as the iterator: `NextMatch()` returns a new `Match` for the next occurrence. The inheritance chain is `Capture` -> `Group` -> `Match`, so a `Match` is a `Group` (group 0) and is a `Capture`.
- `Group` is one capturing group's result. `Capture` is one individual capture. A quantified group captures repeatedly, and .NET is unique in keeping the whole history in `Group.Captures` rather than only the final capture.
- Every static convenience method (`Regex.Match(input, pattern)`, ...) is documented as equivalent to constructing a `Regex` and calling the instance method, with the compiled pattern kept in a bounded static cache.

Quoted text below is verbatim from the learn.microsoft.com `Regex` API pages and the regular-expressions base-types articles.

---

## 1. Compiling: the `Regex` class

```csharp
var r = new Regex(@"\d+");
var r = new Regex(@"\d+", RegexOptions.IgnoreCase | RegexOptions.Multiline);
var r = new Regex(@"\d+", RegexOptions.None, TimeSpan.FromSeconds(2));  // with match timeout
```

A malformed pattern throws `RegexParseException` (sealed, derives from `ArgumentException`). It carries structured error data:

- `Error`: a `RegexParseError` enum value naming what went wrong.
- `Offset`: "the zero-based character offset in the regular expression pattern where the parse error occurs."

Introspection on a compiled instance:

```csharp
r.ToString();      // the pattern string passed to the constructor
r.Options;         // the RegexOptions passed in (inline (?i) flags are NOT reflected here)
r.RightToLeft;     // bool
r.MatchTimeout;    // the timeout for this instance
r.GetGroupNames(); // string[] of group names (numbered groups appear as "0", "1", ...)
r.GetGroupNumbers();
r.GroupNameFromNumber(1);
r.GroupNumberFromName("year");
```

`Regex.CompileToAssembly` (precompiling into a standalone assembly) is obsolete. The source generator replaced it.

### Static methods and the static cache

Every operation exists as a static method taking `(input, pattern[, options[, timeout]])`, documented as "equivalent to constructing a Regex object with the specified pattern and calling the instance method". The compiled program is kept in a static cache. The cache:

- holds 15 entries by default, tunable via the static `Regex.CacheSize` property.
- caches only patterns used in static method calls: "Only regular expressions used in static method calls are cached." Instance regexes are never cached for you. You hold the reference.

---

## 2. The options: `RegexOptions` (all of them)

`RegexOptions` is a `[Flags]` enum:

| Member                    | Value | Inline | Meaning                                                                                                                                                                                     |
| ------------------------- | ----- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `None`                    | 0     | none   | No options set, the default engine behaviour.                                                                                                                                               |
| `IgnoreCase`              | 1     | `i`    | Case-insensitive matching, using the current culture's casing rules by default.                                                                                                             |
| `Multiline`               | 2     | `m`    | `^` and `$` match at the beginning and end of any line, not just of the whole string.                                                                                                       |
| `ExplicitCapture`         | 4     | `n`    | Only explicitly named or numbered groups `(?<name>...)` capture, and plain `(...)` acts as non-capturing.                                                                                   |
| `Compiled`                | 8     | none   | Compile the regex to MSIL instead of interpreting it: faster matching, slower construction.                                                                                                 |
| `Singleline`              | 16    | `s`    | `.` matches every character, including `\n`.                                                                                                                                                |
| `IgnorePatternWhitespace` | 32    | `x`    | Unescaped white space in the pattern is ignored and `#` starts an end-of-line comment. Does not affect character classes, numeric quantifiers, or tokens that start language elements.      |
| `RightToLeft`             | 64    | none   | The search moves from right to left instead of left to right.                                                                                                                               |
| `ECMAScript`              | 256   | none   | ECMAScript-compliant behaviour. "Can be used only in conjunction with the IgnoreCase, Multiline, and Compiled values. The use of this value with any other values results in an exception." |
| `CultureInvariant`        | 512   | none   | Cultural differences in language are ignored (invariant-culture case folding).                                                                                                              |
| `NonBacktracking`         | 1024  | none   | Match "using an approach that avoids backtracking and guarantees linear-time processing in the length of the input."                                                                        |
| `AnyNewLine`              | 2048  | none   | `^`, `$`, `\Z`, and `.` recognize all common newline sequences (`\r\n`, `\r`, `\n`, `\v`, `\f`, `\u0085`, `\u2028`, `\u2029`) instead of only `\n`.                                |

Value 128 is unassigned in the public enum.

### Inline options

Five options can be set inline (`i`, `m`, `n`, `s`, `x`), in two spellings:

- `(?imnsx-imnsx)` applies from that point on. Letters after `-` turn options off. Scope runs "until the end of the enclosing group" (or until toggled again).
- `(?imnsx-imnsx:subexpression)` is scoped to the group.

The rest cannot be set inline. When inline options conflict with the `options` parameter, "the inline options are used." All options are off by default, and `Regex.Options` does not reflect inline toggles.

---

## 3. Matching operations

```csharp
Regex r = new(@"\d+");
r.IsMatch("ab123");          // true   boolean test
r.Match("ab123");            // first Match (find semantics: scans forward)
r.Matches("1 22 333");       // MatchCollection of all matches
r.Count("1 22 333");         // 3      count without materializing matches
```

There is no `matches()`-style whole-string anchoring method. .NET always searches. Whole-string matching is spelled with anchors (`^...$`, or strictly `\A...\z`).

- A failed `Match(...)` never returns null. It returns a `Match` "equal to `Match.Empty`", and `Success` is `false`. Testing `match.Success` is the documented idiom.
- `Match.NextMatch()` "returns a new Match object with the results for the next match, starting at the position at which the last match ended". The original `Match` is not modified.
- `Regex.Matches` returns a `MatchCollection` populated lazily when iterated with `foreach`, but fully and eagerly the moment you touch `Count`, which the docs call "typically ... the more expensive method."

### Zero-width matches in the `NextMatch` chain

"After an empty match, the NextMatch() method advances by one character before trying the next match", guaranteeing progress. The docs' own example, verbatim behaviour:

```csharp
Match m = Regex.Match("abaabb", "a*");
while (m.Success) {
    Console.WriteLine($"'{m.Value}' found at index {m.Index}.");
    m = m.NextMatch();
}
// 'a' at 0, '' at 1, 'aa' at 2, '' at 4, '' at 5, '' at 6   (six matches, per the docs)
```

---

## 4. The result object model

`Capture` (Index, Length, Value, ValueSpan, ToString) -> `Group` (adds Success, Name, Captures) -> `Match` (adds Groups, Empty, NextMatch, Result). All three are immutable with no public constructor.

```csharp
Match m = Regex.Match("2026-09", @"(?<y>\d{4})-(?<mo>\d{2})");
m.Value;               // "2026-09"   (the Match IS group 0)
m.Groups[0].Value;     // "2026-09"
m.Groups["y"].Value;   // "2026"      string indexer
m.Groups[1].Value;     // "2026"      int indexer
m.Index; m.Length;     // 0, 7
m.Groups["mo"].Index;  // 5
```

`GroupCollection` implements both `IReadOnlyList<Group>` and `IReadOnlyDictionary<string, Group>`. The string indexer also accepts "the string representation of the number of a capturing group" (`Groups["1"]`).

### Unmatched groups never throw and are never null

For a group that did not participate, and equally for a group name/number that does not exist in the pattern at all, the indexer "returns a Group object whose Success property is false and whose Group.Value property is Empty":

```csharp
Match m = Regex.Match("b", "(a)?(b)");
m.Groups[1].Success;   // false
m.Groups[1].Value;     // ""  (empty string, not null)
m.Groups[1].Index;     // 0 with Length 0, so never read Index without checking Success
m.Groups["nope"].Success; // false, a typo in a group name just fails
```

The one exception: `Groups[int]` with an out-of-range integer also returns the failed Group, but a conditional `(?(number)...)` referencing a nonexistent numbered group throws `ArgumentException` at parse time.

### Group numbering: named groups come last

"Captures that use parentheses are numbered automatically from left to right ... starting from 1. However, named capture groups are always ordered last, after non-named capture groups." From the substitutions page: in `(\w)(?<digit>\d)`, "the index of the `digit` named group is 2." Mixing named and unnamed groups renumbers nothing visually but everything positionally. This is the numbering trap to know when porting from PCRE.

Duplicate group names are legal: "A group name can be repeated in a regular expression." The `Group`'s value is "determined by the last successful capture", and its `CaptureCollection` accumulates captures from all same-named groups.

---

## 5. Capture history: `CaptureCollection`

The .NET-unique part of the model: "If a quantifier is applied to a capturing group, the CaptureCollection includes one Capture object for each captured substring, and the Group object provides information only about the last captured substring."

```csharp
Match match = Regex.Match("aaabbb", "(a?)*");
Console.WriteLine($"Match: '{match.Value}' at index {match.Index}");
foreach (Capture capture in match.Groups[1].Captures)
    Console.WriteLine($"   Capture: '{capture.Value}' at index {capture.Index}");
// The example displays the following output:
//    Match: 'aaa' at index 0
//    (Group 1: '' at index 3, the LAST capture)
//    Capture 1: 'a'  at index 0
//    Capture 2: 'a'  at index 1
//    Capture 3: 'a'  at index 2
//    Capture 4: ''   at index 3
```

So `(\w+\s*)+`-style patterns lose nothing: every iteration is retrievable with its own `Index`/`Length`/`Value`. PCRE, Java, JS all discard everything but the final iteration. (Caveat: under `NonBacktracking` .NET behaves like those engines and "only supports providing the final capture".) With `RightToLeft`, captures are collected "in innermost-rightmost-first order".

---

## 6. `startat` and the search window

Two windowing semantics coexist, and the difference matters for API design:

- `Match(input, startat)` (also `IsMatch`, `Matches`): matches beginning before `startat` are ignored, but "it doesn't ignore the string before startat. This means that assertions such as anchors or lookbehind assertions still apply to the input as a whole." The docs' example: `(?<=Zip code: )\d{5}` against `"Zip code: 98052"` with `startat: 5` still succeeds. The lookbehind sees text before the start position. Two documented tips: a `^`-anchored pattern (without `Multiline`) "will never be found" when `startat > 0`, and "the `\G` anchor is satisfied at startat" (this is the PHP `preg_match` `$offset` plus `\G` behaviour, almost verbatim).
- `Match(input, beginning, length)`: true substring semantics. "The behavior is exactly as if the input was effectively `input.Substring(beginning, length)`, except that the index of any match is counted relative to the start of input."

In right-to-left mode, "the right-to-left scan begins at the character at `startat` - 1", and a `\G` at the right end anchors the match to end at `startat` - 1.

---

## 7. Replacement

```csharp
Regex.Replace("a1b2", @"\d", "#");                    // "a#b#"  replaces ALL matches by default
new Regex(@"\d").Replace("a1b2", "#", 1);             // "a#b2"  count caps replacements
new Regex(@"\d").Replace("a1b2", "#", 1, startat: 2); // count + start position
```

### The substitution language (complete)

Substitutions "are the only special constructs recognized in a replacement pattern". Regex character escapes (`\n`, `\t`, ...) are not processed there. The full documented set:

| Substitution | Meaning                                                                                                                  |
| ------------ | ------------------------------------------------------------------------------------------------------------------------ |
| `$number`    | Last substring matched by capturing group number.                                                                      |
| `${name}`    | Last substring matched by the named group. If name is digits and no such name exists, it is treated as a group number. |
| `$$`         | A literal `$`.                                                                                                           |
| `$&`         | A copy of the whole match.                                                                                               |
| `` $` ``     | All input text before the match (from the original input, even on later matches).                                      |
| `$'`         | All input text after the match.                                                                                        |
| `$+`         | The last group captured (the highest-numbered group that captured).                                                      |
| `$_`         | The entire input string.                                                                                                 |

Failure mode is silence, not errors: an invalid `$number` or `${name}` "is interpreted as a literal character sequence." `$11` means group 11 if it exists ("All digits that follow `$` are interpreted as belonging to the number group"). Write `${1}1` for group 1 then a literal `1`. There is no `$0`. The whole match is `$&`.

### Callback replacement: `MatchEvaluator`

```csharp
public delegate string MatchEvaluator(Match match);

Regex.Replace("1 22", @"\d+", m => $"<{m.Value}>");   // "<1> <22>"
```

The delegate is "called each time a regular expression match is found" and its return value is substituted verbatim (no `$` processing). `Match.Result(string replacement)` exposes the substitution expansion for a single match.

### Escaping

`Regex.Escape(string)` "escapes a minimal set of characters (`\`, `*`, `+`, `?`, `|`, `{`, `[`, `(`, `)`, `^`, `$`, `.`, `#`, and white space)". It deliberately does not escape `]` and `}`. Escaping `#` and white space makes the result safe under `IgnorePatternWhitespace`. `Regex.Unescape` reverses it. There is no quoting construct for replacement text. To insert user text literally, double its `$` characters or use a `MatchEvaluator`.

---

## 8. Splitting

```csharp
new Regex(",").Split("a,b,,c");       // ["a", "b", "", "c"]  adjacent matches -> empty string kept
new Regex(",").Split("a,b,c", 2);     // ["a", "b,c"]         count = max pieces, remainder in last
new Regex("(,)").Split("a,b");        // ["a", ",", "b"]      captured text IS included
```

The documented rules:

- Captured text is included in the result array, but "is not counted toward the count limit". (Perl style. PHP needs `PREG_SPLIT_DELIM_CAPTURE` to opt in.)
- "If two adjacent matches are found, an empty string is placed in the array." Nothing is dropped. There is no Java-style trailing-empty stripping, filtering is your job.
- `count` "specifies the maximum number of substrings into which the input string can be split; the last string contains the unsplit remainder." `count` = 0 means split as many times as possible. Empty strings do count toward `count`.
- `startat` starts the delimiter search at a position (with `Match(String, Int32)` window semantics).
- A pattern that can match the empty string splits into single-character strings, "because the empty string delimiter can be found at every location."
- With `RightToLeft`, matching runs right to left, and `Split` reverses the pieces so the array still reads left to right.
- No match: the array contains the input as its single element.

`Regex.EnumerateSplits` (span-based) is the same operation as a lazy enumerator of `System.Range` slices, with two differences: it does not include capture-group text, and under `RightToLeft` it yields splits in found order without reversing.

---

## 9. Timeouts, in full

.NET builds wall-clock timeouts into the engine itself:

- Per instance: `new Regex(pattern, options, TimeSpan matchTimeout)`, readable via `Regex.MatchTimeout`. Valid range: greater than zero and less than "approximately 24 days". Out of range throws `ArgumentOutOfRangeException`.
- Per static call: every static method has a `TimeSpan matchTimeout` overload, which "overrides any default time-out value defined for the application domain."
- Process/AppDomain default: set via `AppDomain.SetData` on the `REGEX_DEFAULT_MATCH_TIMEOUT` property.
- The default default: `Regex.InfiniteMatchTimeout`. "By default, the time-out interval is set to Regex.InfiniteMatchTimeout and the regular expression engine does not time out."

On expiry the engine throws `RegexMatchTimeoutException` (derives from `TimeoutException`, not `ArgumentException`), carrying `Input`, `Pattern` and `MatchTimeout`. Time-outs from excessive backtracking "are always reproducible". The engine "maintains its state so that any future invocations return the same result, as if the exception did not occur", and the recommended retry is waiting "a brief, random time interval" a small number of times. The guidance: "we recommend that you always set a time-out interval if your regular expression relies on backtracking or operates on untrusted inputs".

---

## 10. Four execution strategies, one API

1. Interpreter (default): pattern is parsed to a node tree, optimized and interpreted.
2. `RegexOptions.Compiled`: same pipeline, then reflection-emit to MSIL. "Maximize run-time performance at the expense of initialization time". On platforms that forbid dynamically generated code, "Compiled becomes a no-op."
3. `RegexOptions.NonBacktracking`: automata-based engine that "avoids backtracking and guarantees linear-time processing in the length of the input." Documented restrictions:
   - cannot be combined with `RightToLeft`, `ECMAScript` (or `AnyNewLine`).
   - the pattern may not contain: atomic groups, backreferences, balancing groups, conditionals, lookarounds, or the `\G` anchor.
   - capture semantics change: a capture group in a loop "only supports providing the final capture", unlike the default engines' full `CaptureCollection` history.
   - it guards against expensive input, not malicious patterns: "The .NET regex engine assumes the pattern is trusted."
4. Source generator, `[GeneratedRegex]`: compile-time codegen for patterns known at compile time.

```csharp
[GeneratedRegex("abc|def", RegexOptions.IgnoreCase, "en-US")]
private static partial Regex AbcOrDefGeneratedRegex();
// use: AbcOrDefGeneratedRegex().IsMatch(text)
```

The attribute targets partial, parameterless, non-generic methods or get-only properties returning `Regex` (C# only). Constructors: `(pattern)`, `(pattern, options)`, `(pattern, options, matchTimeoutMilliseconds)`, `(pattern, options, cultureName)`. The generator emits a cached singleton `Regex` subclass as readable, debuggable C# (set breakpoints in your own regex's matching code), with `RegexOptions.Compiled` ignored as redundant. Documented benefits: `Compiled`-level throughput, no runtime parse/compile cost at startup, AOT friendly, trimming friendly. Documented fallbacks: for `NonBacktracking` and for case-insensitive backreferences it "will instead fall back to caching a regular Regex instance." One subtle semantic: with `IgnoreCase` the casing table is baked in at compile time, whereas the runtime engines consult the current runtime's table.

---

## 11. Span-based, allocation-free matching

- `Capture.ValueSpan`: a `ReadOnlySpan<char>` view of any capture.
- `Regex.IsMatch(ReadOnlySpan<char> ...)` overloads.
- `Regex.Count(...)` for strings and spans: match count with nothing materialized.
- `Regex.EnumerateMatches(ReadOnlySpan<char> ...)` returns a `Regex.ValueMatchEnumerator` yielding `ValueMatch`: a `readonly ref struct` exposing only `Index` and `Length`. No `Value` string and no groups. It allocates nothing by design. Slice the input span yourself.
- `Regex.EnumerateSplits(ReadOnlySpan<char> ...)` returns a `Regex.ValueSplitEnumerator` (`ref struct`) yielding a `System.Range` per split. Matching is lazy ("one match being performed per MoveNext() call") and mutating the input between `MoveNext` calls is unsupported.

Full `Match`/`Group`/`Capture` trees exist only for `string` inputs. The span APIs deliberately trade the object model away.

---

## 12. The pattern syntax .NET supports (the deltas that matter)

- Escapes: `\a \b(class) \t \r \v \f \n \e`, octal `\nnn` (two or three digits), hex `\xnn` (exactly two digits), control `\cX`, and `\unnnn` (exactly four hex digits, a UTF-16 code unit). Perl's variable-length `\x{....}` "is not supported by .NET. Instead, use `\unnnn`." No `\N{name}`. `\v` is the vertical-tab character, not a whitespace class.
- Classes: `[...]`, `[^...]`, ranges, `.`, `\w \W \s \S \d \D` (Unicode-based by default, the canonical `\w` is `[\p{Ll}\p{Lu}\p{Lt}\p{Lo}\p{Nd}\p{Pc}\p{Lm}]`), Unicode general categories `\p{Lu}` and named blocks `\p{IsCyrillic}` (blocks, not scripts), and class subtraction `[base_group-[excluded_group]]` (below). No class intersection operator (no Java `&&`).
- Anchors: `^ $ \A \Z \z \b \B` and `\G` ("the match must start at the position where the previous match ended").
- Groups: `(...)`, `(?:...)`, named groups in both spellings `(?<name>...)` and `(?'name'...)`, balancing groups (below), inline-option groups `(?imnsx-imnsx:...)`, atomic groups `(?>...)`, lookahead `(?=) (?!)` and lookbehind `(?<=) (?<!)`. The docs place no fixed-length restriction on lookbehind. It is implemented "using a right-to-left search starting at the current match location", so variable-length lookbehind works.
- Backreferences: `\1`..., named `\k<name>` and `\k'name'`. A backreference to an undefined group number is a parse error (`ArgumentException`). Octal disambiguation is rule-based. `\1`-`\9` are always backreferences. `\10` and up is a backreference if that group exists, else octal. A backreference to a group that captured nothing "is undefined and never matches".
- Conditionals: both forms (section 14).
- Comments: inline `(?#comment)` (ends at the first `)`) and `#`-to-end-of-line under `x` mode.
- Quantifiers: greedy and lazy only, `* + ? {n} {n,} {n,m}` and their `?`-suffixed lazy forms. There is no possessive quantifier syntax. Atomic groups are the sanctioned equivalent (`(?>a+)` where PCRE writes `a++`).

### Character-class subtraction

`[base_group-[excluded_group]]`, nestable: `[a-z-[m]]`, `[a-z-[djp]]`, `[a-z-[m-p]]`, `[a-z-[d-w-[m-o]]]` (evaluated innermost-outward, yielding `[abcmnoxyz]`), and full class algebra like `[\u0000-\uFFFF-[\s\p{P}\p{IsGreek}\x85]]`. The docs' runnable example: `^[0-9-[2468]]+$` against `{"123", "13579753", "3557798", "335599901"}` matches only `13579753` and `335599901`.

---

## 13. Balancing groups: .NET's substitute for recursion

The construct is `(?<name1-name2>subexpression)` (or `(?'name1-name2'...)`). Documented semantics: it "deletes the definition of a previously defined group and stores, in the current group, the interval between the previously defined group and the current group. ... this construct lets you use the stack of captures for group name2 as a counter for keeping track of nested constructs." Each capture of `name2` is a push and each `(?<-name2>...)` match is a pop.

The docs' worked example, matching balanced angle brackets:

```csharp
string pattern = "^[^<>]*" +
                 "(" +
                 "((?'Open'<)[^<>]*)+" +
                 "((?'Close-Open'>)[^<>]*)+" +
                 ")*" +
                 "(?(Open)(?!))$";
Match m = Regex.Match("<abc><mno<xyz>>", pattern);
// Documented output (abridged): the match succeeds on the whole input;
// Group "Open" ends EMPTY (every push was popped);
// Group 5 ("Close") holds the balanced spans in its Captures:
//    Capture 0: abc
//    Capture 1: xyz
//    Capture 2: mno<xyz>
```

The two idioms: `(?'Close-Open'>)` pops one `Open` per `>` (backtracking if the stack is empty, i.e. an unbalanced closer), and the trailing `(?(Open)(?!))` fails the match via an always-failing lookahead if any `Open` remains (an unclosed opener). This is stack manipulation exposed in pattern syntax. Strictly less convenient than PCRE's `(?R)`/`(?1)` recursion, but it can capture every nesting level (see Group 5 above), which recursion cannot.

---

## 14. Conditionals

Both PCRE-style forms exist, with .NET-specific resolution rules:

- Expression test: `(?(expression)yes|no)`. expression is treated as a zero-width assertion (the construct "is equivalent to `(?(?=expression)yes|no)`"). Docs example: `\b(?(\d{2}-)\d{2}-\d{7}|\d{3}-\d{2}-\d{4})\b` matches EINs and SSNs.
- Capture test: `(?(name)yes|no)` / `(?(number)yes|no)`. Tests whether the group has matched.

The ambiguity rules: if expression names an existing group, it becomes a capture test. A name matching no group degrades to an expression test. A number matching no group throws `ArgumentException`. To force an expression test, write the assertion explicitly: `(?((?=expression))yes|no)`.

---

## 15. Right-to-left and ECMAScript modes

`RightToLeft` reverses the scan ("the right-to-left search automatically begins at the last character position of the string") and "reverses the order in which the regular expression pattern is evaluated". The docs' example: `Regex.Match("abcabc", @"\1(abc)", RegexOptions.RightToLeft)` matches `abcabc`, because `(abc)` is evaluated before the `\1` that textually precedes it. Lookarounds keep their absolute directions. Matches are found last-first: `\bb\w+\s` on `"build band tab"` yields `band ` then `build `.

`ECMAScript` switches to JavaScript-compatible semantics. Combinable only with `IgnoreCase`, `Multiline` and `Compiled` (anything else: `ArgumentOutOfRangeException`). Documented differences: ASCII-only character classes (no `\p{}`, `\w` becomes `[a-zA-Z_0-9]`), self-referencing capture groups behave per iteration, and octal-versus-backreference ambiguity resolves leniently (an undefined `\9` is a literal instead of a parse error).

---

## 16. What .NET does NOT have (versus PCRE)

Checked against the .NET language quick reference. None of these constructs appears anywhere in it:

- No possessive quantifiers (`*+`, `++`, `?+`, `{n,m}+`). Atomic groups `(?>...)` are the only backtracking suppressor.
- No `\K` (reset match start).
- No recursion or subroutine calls (`(?R)`, `(?1)`, `(?&name)`), no `(?(DEFINE)...)`. Balancing groups are the weaker, stack-based substitute.
- No branch reset `(?|...)`.
- No backtracking-control verbs (`(*SKIP)`, `(*FAIL)`, `(*COMMIT)`, ...) and no callouts. The timeout is the only mid-match escape hatch.
- No `\Q...\E` literal quoting in the pattern (use the API: `Regex.Escape`).
- No `\R` (any newline), no `\X` (grapheme cluster), no `\h/\H` horizontal-whitespace classes (and `\v` means the VT character). `AnyNewLine` fixes only the anchor/`.` side of newline handling, not `\R`.
- No `\N`, no `\x{...}`, no script properties (`\p{Greek}`): Unicode `\p{}` covers general categories and named blocks (`\p{IsGreek}`) only.
- No partial/incremental matching (nothing like PCRE2's `PCRE2_PARTIAL_HARD`), no match/depth limits. Resource control is wall-clock (`MatchTimeout`) instead of operation count.
- The engine is UTF-16-code-unit based (`\unnnn` "matches a UTF-16 code unit"). There is no byte mode or `\C`.

In the other direction, .NET has, and PCRE2 lacks: full capture history (`CaptureCollection`, PCRE2's ovector keeps only each group's final capture), balancing groups, right-to-left mode, an in-API linear-time engine (`NonBacktracking`), wall-clock timeouts and class subtraction.

---

## 17. Gotchas, tricks, workarounds

### Named groups renumber to the end
`(\w)(?<digit>\d)`: `digit` is group 2, fine. But add a named group before unnamed ones and the positional intuition breaks, because all named groups number after all unnamed ones. Mixing styles in one pattern is the classic .NET review comment, and the docs' own advice elsewhere amounts to "don't". `ExplicitCapture`/`(?n)` sidesteps it by making plain parentheses non-capturing.

### Failure is silent in the result tree
`Groups["typo"]` and `Groups[99]` return a failed `Group` (Success false, Value ""), never throw. A misspelled group name produces empty strings, not errors. Check `Success`, and remember `Index`/`Length` of a failed group are 0/0, not -1.

### `$` (and `\Z`) match before a final `\n`, not before `\r\n`
"By default, the match must occur at the end of the string or before `\n` at the end of the string." Strict end is `\z`. Since only `\n` terminates lines, `.+$` in multiline mode on Windows text captures a trailing `\r`. The documented workaround is `\r?$` (which pulls `\r` into the match). `AnyNewLine` treats `\r\n` atomically.

### Replacement strings are their own tiny language
Only `$`-substitutions are special. Character escapes are not recognized, so a `@"\n"` replacement inserts backslash-n. An invalid `$number`/`${name}` just becomes literal text (no exception, unlike Java). Literal `$` must be `$$`. For untrusted replacement text, escape `$` yourself or use a `MatchEvaluator`. There is no `quoteReplacement` equivalent.

### The static cache is small and static-only
Fifteen entries, only for static-method patterns. An instance `new Regex(...)` in a hot loop re-parses every time and is cached nowhere. The documented order of preference: source-generated, else a stored `Regex` instance, else static methods, never construct-per-call.

### Culture-sensitive case folding (the Turkish-I hole)
`IgnoreCase` folds via the current culture. The docs' example: matching `"FILE://"` case-insensitively against `"file://..."` under culture `tr-TR` fails to match (dotless-i rules), and the URL guard is gone with no error anywhere. Fix: `RegexOptions.CultureInvariant`. Related: `[GeneratedRegex]` bakes the casing table at compile time, so Unicode updates change behaviour only on recompile.

### Catastrophic backtracking, quantified by the docs
`^(a+)+$` against a 27-character input of a's ending in `!` takes ~5.2 s in the docs' measurement, versus ~2 ms for the same-length matching input (the docs call the non-matching case an O(2^n) operation). Mitigations, in documented order: set a timeout, bound input length, rewrite with atomic groups (the docs' IPv6-ish example drops from 27.4 s to 0.0001 s by wrapping the inner loops in `(?>...)`) or lookarounds, or switch to `NonBacktracking` when the pattern uses none of the unsupported constructs.

### `startat` is not a substring boundary
`Match(input, startat)` lets lookbehind and word boundaries see text before `startat` (by design, per the Zip-code example), and `^`-anchored patterns never match with `startat > 0`. For "as if the string started here", use `Match(input, beginning, length)`. To pin a match exactly at `startat`, anchor with `\G`.

### `MatchCollection.Count` defeats laziness
`foreach` over `Matches(...)` runs match-by-match. Touching `Count` (or indexing) forces the entire input to be scanned first. If you only need the count, `Regex.Count` does it without building `Match` objects at all.

### `NonBacktracking` is not a free lunch
It throws at construction for atomic groups, backreferences, balancing groups, conditionals, lookarounds and `\G`. It cannot combine with `RightToLeft`/`ECMAScript`. And quantified groups keep only their final capture, so code that relies on `CaptureCollection` history sees less data with no error.

### Duplicate names and named-numeric groups
`(?<2>\w)` is legal, a group explicitly named "2". The docs show `\k<1>` resolving to ordinal group 1 only if no group is named "1", and throwing `ArgumentException` when explicit numeric names shadow ordinals. Treat numeric group names as a misfeature to ban in style review.
