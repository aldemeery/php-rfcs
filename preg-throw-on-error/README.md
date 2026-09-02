# PREG_THROW_ON_ERROR

Regular expressions fail, and PHP barely tells you when they do. A bad pattern or bad UTF-8 hands you `false` or `null`, which a quick truthiness check can't tell apart from a clean no-match. This RFC proposes `PREG_THROW_ON_ERROR`, a flag you pass to any `preg_*()` function to turn a PCRE error into a `\PregException` you can `catch`.

Catching the error yourself could look like this:

```php
if (preg_match($pattern, $subject, $matches) === false) {
    throw new RuntimeException(preg_last_error_msg());
}
```

Nothing requires that check, and even if you write it, that's not the end of it, because:

- `0`, `false` and `null` don't line up across the functions.
- `preg_last_error()` is overwritten by your next call, so read it now or lose it.
- Compile failures behave differently from runtime ones.

Which is just a lot of ceremony for "did my regex work?"

PHP has fixed this problem twice before. `json_decode()` got `JSON_THROW_ON_ERROR` in 7.3, and `ext/filter` got `FILTER_THROW_ON_FAILURE` in 8.5. Both let you opt a single call into throwing instead of returning a sentinel you inspect by hand.

PCRE is the one that never got it.

## Proposal

A new constant, `PREG_THROW_ON_ERROR`, is added. Pass it in the `$flags` argument of any `preg_*()` function that has one, and any PCRE error the call records in `preg_last_error()` is additionally thrown as a `\PregException`, so you can `catch` it instead of inspecting the return value by hand.

```php
try {
    $count = preg_match_all($pattern, $subject, $matches, PREG_THROW_ON_ERROR);
    // From here on, $count is a real result. There was no error.
} catch (\PregException $e) {
    // $e->getMessage() and $e->getCode() are exactly what
    // preg_last_error_msg() and preg_last_error() would have told you.
}
```

That is all it does. The error is exactly the one you'd get without the flag. You just receive it as an exception.

### Which functions accept it

Every `preg_*()` function that does matching accepts the flag. That is all eight of them:

- `preg_match()`
- `preg_match_all()`
- `preg_replace()`
- `preg_filter()`
- `preg_replace_callback()`
- `preg_replace_callback_array()`
- `preg_split()`
- `preg_grep()`

`preg_replace()` and `preg_filter()` are the only two functions in the family that _didn't_ have a `$flags` parameter, so they gain one.

```php
function preg_replace(string|array $pattern, string|array $replacement, string|array $subject, int $limit = -1, &$count = null, int $flags = 0): string|array|null {}

function preg_filter(string|array $pattern, string|array $replacement, string|array $subject, int $limit = -1, &$count = null, int $flags = 0): string|array|null {}
```

`preg_quote()`, `preg_last_error()` and `preg_last_error_msg()` don't take the flag. The first does no matching and cannot raise a PCRE error, and the last two exist precisely to report the error state and have nothing to throw.

### The exception

A new class is added.

```php
/**
 * @strict-properties
 */
class PregException extends \Exception {}
```

It lives in the global namespace, it extends `\Exception`, and it is not `final`.

When it's thrown:

- `$e->getCode()` equals what `preg_last_error()` returns for the same call, that is one of the existing `PREG_*_ERROR` constants.
- `$e->getMessage()` equals what `preg_last_error_msg()` returns for the same call.

The exception is built from the same error state those functions report, so it can never disagree with them.

```php
try {
    preg_match('//u', "\xff", $m, PREG_THROW_ON_ERROR);
} catch (\PregException $e) {
    $e->getCode() === preg_last_error();          // true
    $e->getMessage() === preg_last_error_msg();   // true
    // "Malformed UTF-8 characters, possibly incorrectly encoded", code PREG_BAD_UTF8_ERROR
}
```

### Compilation errors and execution errors

The flag covers both classes of PCRE failure.

An **execution error** like bad UTF-8, a blown backtrack or recursion limit, or a JIT stack overflow already sets a specific `preg_last_error()` code and message today. Under the flag, the exception carries that same code and message. For example, a backtrack blowout throws `PREG_BACKTRACK_LIMIT_ERROR` with "Backtrack limit exhausted", and every execution error maps the same way.

A **compilation error** like a malformed pattern, a bad delimiter, or an unknown modifier is the one case worth spelling out.

A compile failure does two things today, with or without the flag:

- It sets the generic code `PREG_INTERNAL_ERROR` in `preg_last_error()`, whose message is the flat string "Internal error".
- It emits a warning carrying the real detail from PCRE, something like `Compilation failed: missing terminating ] for character class at offset 4`.

Those two channels have always disagreed. The warning is specific, `preg_last_error_msg()` is generic. This RFC changes neither. Under the flag both still happen, and the exception is added on top, carrying the same generic code and message the error functions report.

```php
try {
    preg_match('/[/', 'subject', $m, PREG_THROW_ON_ERROR);
} catch (\PregException $e) {
    $e->getMessage();   // "Internal error"
    $e->getCode();      // PREG_INTERNAL_ERROR
}
// The detailed "Compilation failed: ..." warning is still emitted, as always.
```

So the detailed message is not lost. It stays where it has always lived, in the warning. The exception carries the generic code and message the error functions report, which keeps the mirror exact. Making `preg_last_error_msg()` itself carry the detail is a separate improvement. See [Future Scope](#future-scope).

### Arrays

Several of these functions take arrays. `preg_replace()` accepts an array of patterns and/or subjects, and `preg_grep()` filters an array of inputs. One call can then run many PCRE operations, and more than one can fail.

The flag does not change how arrays are processed. It throws exactly the error `preg_last_error()` would hold after the same call without the flag.

```php
// Without the flag, the good 'ok' entry is processed last and clears the
// error, so preg_last_error() is 0. With the flag this does not throw.
preg_replace('//u', 'x', ["\xff", 'ok'], -1, $count, PREG_THROW_ON_ERROR);

// The failing entry is processed last here, so preg_last_error() holds its
// error and the flag throws it.
preg_replace('//u', 'x', ['ok', "\xff"], -1, $count, PREG_THROW_ON_ERROR);
```

This is deliberate. The flag mirrors `preg_last_error()` and adds no error semantics of its own. Different functions already leave different state here, `preg_grep()` stops at the first failing entry while `preg_replace()` runs them all, and the flag follows whatever each one does. Whether the `preg_*()` functions should stop at the first failing array entry is a separate question about those functions, one that would apply with or without the flag, and it is left open here.

### By-reference outputs on the throwing path

Some of these functions write through reference parameters, `$matches` for the match functions and `$count` for the replace family. When the exception is thrown, those outputs hold exactly what the same call without the flag would leave in them.

If you catch a `PregException`, don't rely on `$matches` or `$count`. Read your result from the return value on the success path, not from the out-parameters in the `catch`.

### Errors from user callbacks are never masked

`preg_replace_callback()` and `preg_replace_callback_array()` run your code mid-operation.

If your callback throws, that exception wins. The flag never replaces or swallows it. And if your callback runs its own `preg_*()` call that fails, that error is not blamed on the outer replace. A successful outer call stays successful. The flag reports the error of _the call it was passed to_, nothing else.

```php
// This returns "Y". The nested failing match inside the callback does not
// make the (successful) outer replace throw.
$out = preg_replace_callback('/x/', function ($m) {
    @preg_match('//u', "\xff");   // unrelated, and fails
    return 'Y';
}, 'x', -1, $count, PREG_THROW_ON_ERROR);
```

## Backward Incompatible Changes

None.

The flag is opt-in and the constant is new, so no existing code changes behaviour. Without it, every `preg_*()` call behaves exactly as it does today, byte for byte. The public C API is unchanged as well, so extensions built against `ext/pcre` keep working without a recompile.

## Proposed PHP Version(s)

The next PHP feature release after 8.6.

## RFC Impact

### To the Ecosystem

IDEs, language servers and static analyzers ship their own stubs for the `preg_*()` functions. They pick up the usual additions: the new `$flags` parameter on `preg_replace()` and `preg_filter()`, the `PREG_THROW_ON_ERROR` constant, and the `\PregException` class. That is the same stub refresh any new function, constant or class calls for.

Formatters and linters see no syntax change.

Userland libraries are unaffected unless they choose to adopt the flag, since it is opt-in.

### To Existing Extensions

Confined to `ext/pcre`. Nothing outside it changes, and the public C API is untouched.

### To SAPIs

None.

### To Opcache

None.

The flag lives entirely in the runtime `preg_*()` functions. There are no new opcodes, no compiler changes, and the flag never reaches the compiled-pattern cache key, so it can't affect caching or the JIT.

### New Constants

`PREG_THROW_ON_ERROR`, the opt-in flag.

### New Classes

`\PregException` (extends `\Exception`).

## Future Scope

**Richer compile-error reporting.** The detailed PCRE compile message (`Compilation failed: ... at offset N`) is reachable only through the warning today, never through `preg_last_error_msg()`. Teaching the error functions to carry that detail would let the exception carry it too, with the invariant intact. That changes the non-flag path, so it belongs in its own RFC.

## Patches and Tests

A complete implementation is available, covering all eight functions, the new exception, the array and callback paths, and the by-reference behaviour.

The tests assert the core invariant directly, that the exception's code and message match `preg_last_error()` and `preg_last_error_msg()` byte for byte, across both compile and execution errors, and confirm that a call without the flag behaves exactly as before.

Pull request: https://github.com/php/php-src/pull/22797

## References

- [JSON_THROW_ON_ERROR (PHP 7.3)](https://wiki.php.net/rfc/json_throw_on_error)
- [FILTER_THROW_ON_FAILURE (PHP 8.5)](https://wiki.php.net/rfc/filter_throw_on_failure)
- [Namespaces in bundled PHP extensions](https://wiki.php.net/rfc/namespaces_in_bundled_extensions)
- [Throwable hierarchy policy for extensions](https://wiki.php.net/rfc/extension_exceptions)
- [Pre-RFC discussion on the internals list](https://news-web.php.net/php.internals/131783)
