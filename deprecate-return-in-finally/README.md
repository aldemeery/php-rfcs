# How common is `return` inside `finally` in real PHP code?

A `return` statement inside a `finally` block silently discards any pending exception or return value from the corresponding `try`/`catch`.
This is a survey of how often it actually occurs in the wild, and whether each occurrence is a latent bug or intentional.

## Method

The detector is a patched PHP that emits an `E_DEPRECATED` at compile time when a `finally` block contains a `return` ([aldemeery/php-src@deprecate-return-in-finally](https://github.com/aldemeery/php-src/tree/deprecate-return-in-finally)).
So `php -l` over a file reports exactly what would ship.

Corpus: the 4992 most-installed Composer packages via [nikic/popular-package-analysis](https://github.com/nikic/popular-package-analysis).

## Steps
1. build the patched php (the branch above)
2. fetch the corpus
   ```bash
   git clone https://github.com/nikic/popular-package-analysis && cd popular-package-analysis && php download.php 0 5000 && ./extract.sh
   ```
3. lint every file containing the `finally` token with the patched php and collect the hits
   ```
   grep -rlIiw finally sources --include='*.php' | xargs -P"$(nproc)" -n40 sh -c 'for f; do /path/to/patched/php -n -l "$f" 2>&1; done' _ | grep "Returning from a finally block"
   ```

## Result

- 525,825 PHP files scanned, 3,012 contain the `finally` keyword.
- `return` inside `finally`: 12 occurrences, in 9 of the 4992 packages (0.18%).
- 1 parse-error file among candidates (too old to compile on 8.6)...negligible blind spot.

## The 12 occurrences

Each links to the exact surveyed commit...click and judge for yourself:
  1. [ibexa/admin-ui (swallows the exceptions its own docblock declares)](https://github.com/ibexa/admin-ui/blob/2322d54/src/bundle/Controller/ContentTypeController.php#L834)
  2. [shopware/core (eats thumbnail failures and still reports success)](https://github.com/shopware/core/blob/e8079a0/Content/Media/Thumbnail/ThumbnailService.php#L294)
  3. [amphp/http-server (drops exceptions when the stream is already gone)](https://github.com/amphp/http-server/blob/b306134/src/Driver/Http2Driver.php#L1322)
  4. [dvdoug/PHPCoord (deliberate...finally is the method's return)](https://github.com/dvdoug/PHPCoord/blob/ced02c4/src/Point/CompoundPoint.php#L131)
  5. [dvdoug/PHPCoord (again)](https://github.com/dvdoug/PHPCoord/blob/ced02c4/src/Point/GeocentricPoint.php#L148)
  6. [dvdoug/PHPCoord (again)](https://github.com/dvdoug/PHPCoord/blob/ced02c4/src/Point/GeographicPoint.php#L221)
  7. [dvdoug/PHPCoord (again)](https://github.com/dvdoug/PHPCoord/blob/ced02c4ad44aa4a558f69d53af4834a9d50ab2aa/src/Point/ProjectedPoint.php#L242-L247)
  8. [spatie/ray (delibrate...any failure just returns false)](https://github.com/spatie/ray/blob/2da2079/src/Client.php#L71)
  9. [cakephp/cakephp (catch consumed the exception...finally just returns array)](https://github.com/cakephp/cakephp/blob/eef91f28de119bee5536905244d2096f752f2920/src/Database/Query.php#L1748-L1755)
  10. [hyperf/http-server (catch consumed the exception...finally emits response)](https://github.com/hyperf/http-server/blob/80c52d4/src/Server.php#L140)
  11. [silverstripe/framework (catch consumed the mysqli error)](https://github.com/silverstripe/silverstripe-framework/blob/9c59c42/src/ORM/Connect/MySQLiConnector.php#L213)
  12. [symfony/flex (try can't actually throw)](https://github.com/symfony/flex/blob/4a6d98e/src/PackageResolver.php#L88)

## Summary

- 3 are latent bugs the deprecation would catch
- 9 deliberately rely on the discard or at least have it harmless.

So `return`-in-`finally` is very rare (0.18% of top packages) and where it *does* occur it is a real source of silent bugs in serious projects, but it is not ~100% accidental...roughly two thirds of occurrences are intentional (or at least harmless) and would need a trivial refactor under a deprecation.
