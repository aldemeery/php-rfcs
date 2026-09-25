# PCRE2 capabilities PHP cannot reach

One runnable pcre2test file per PCRE2 capability that `preg_*` cannot reach today. Each file carries the docs link, the reason PHP cannot reach it, an explanation and an `# Expect:` claim above every block. `index.md` is the map.

## Running

One demo:

```bash
./pcre2test -q 01-partial-matching.pcre2test
```

All of them:

```bash
for f in *.pcre2test; do ./pcre2test -q "$f"; done
```

pcre2test echoes each pattern, subject and comment with the engine's result under it. The results are what the `# Expect:` comments claim. Demo 08 writes `/tmp/pcre2-gap-08.bin` as a side effect.

## The binary

The committed `pcre2test` is a Linux x86-64 build of PCRE2 10.49-DEV with JIT and Unicode, the binary every Expect in this folder was verified against. On another platform, or to build your own, copy-paste this (needs git, cmake and a C compiler):

```bash
git clone --depth 1 --recurse-submodules --shallow-submodules https://github.com/PCRE2Project/pcre2.git pcre2-src
cmake -S pcre2-src -B pcre2-src/build -DPCRE2_SUPPORT_JIT=ON -DCMAKE_BUILD_TYPE=Release -DPCRE2_BUILD_PCRE2GREP=OFF
cmake --build pcre2-src/build --target pcre2test --parallel
cp pcre2-src/build/pcre2test .
./pcre2test -version
```

JIT must be on, demo 09 drives the JIT stack. The submodule flags matter too: the JIT sources live in the sljit submodule and a plain clone fails to build. Any PCRE2 from 10.47 up runs all sixteen demos.
