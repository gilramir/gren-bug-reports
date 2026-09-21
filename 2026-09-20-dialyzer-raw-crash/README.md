# `dialyzer --raw` crashes as soon as it has a warning to print

Dialyzer is the static analyser that ships with Erlang/OTP. `--raw` asks it to
print its warnings as Erlang terms instead of as English sentences, which is
the form a tool would read. It works when there is nothing to report. The
first warning it has to print crashes the Erlang runtime during boot, with a
`function_clause` in `dialyzer_cl:set_warning_id/2`, and leaves an
`erl_crash.dump` behind. The same analysis without `--raw` prints the warning
and exits 2, as documented.

## Run it

```sh
./run.sh
```

That is the whole reproduction. It needs [devbox](https://www.jetify.com/devbox),
which installs the pinned Erlang/OTP 27 into this directory and nowhere else;
the script re-runs itself inside it. The first run downloads Erlang, which
takes a minute or two. Everything the script makes goes into `out/`.

It does three things and says what it is doing before each:

1. **Builds a PLT** (about ten seconds). A PLT is Dialyzer's cache of what it
   knows about the standard library, and it refuses to analyse anything without
   one. It prints warnings about OTP's own code while it builds; those are
   normal and go to `out/plt-build.log`.
2. **Runs Dialyzer on `src/m.erl` the ordinary way.** This works: it prints
   `m.erl:11:1: Function g/0 has no local return` and exits 2, which is
   Dialyzer's status for "there were warnings".
3. **Runs exactly the same command with `--raw` added.** This crashes.

It ends with one of two lines:

```
BUG REPRODUCED: step 3 printed 'Runtime terminating during boot'
```

or `NOT REPRODUCED`, with the Erlang version printed at the top so it is clear
which one was tried.

## What you should see

```
=== 2. the ordinary run: this works ===
  Checking whether the PLT otp.plt is up-to-date... yes
  Proceeding with analysis...
m.erl:11:1: Function g/0 has no local return
 done in 0m0.07s
done (warnings were emitted)
--- dialyzer exited 2 (2 means it had warnings, which is the point)

=== 3. the same analysis with --raw: this crashes ===
  Checking whether the PLT otp.plt is up-to-date... yes
  Proceeding with analysis...{error,function_clause,[{dialyzer_cl,'-set_warning_id/2-inlined-0-',[{warn_return_no_exit,{".../src/m.erl",{11,1}},{no_return,[only_normal,g,0]}}],[{file,"dialyzer_cl.erl"},{line,697}]},{lists,map,2,...},{dialyzer_cl,print_warnings,1,[{file,"dialyzer_cl.erl"},{line,812}]},...]}
Runtime terminating during boot ({function_clause,[{dialyzer_cl,'-set_warning_id/2-inlined-0-',...]})

Crash dump is being written to: erl_crash.dump...done
--- dialyzer exited 1
```

## Without devbox

If Erlang/OTP is already installed, the three steps by hand are:

```sh
dialyzer --build_plt --output_plt otp.plt --apps erts kernel stdlib
dialyzer --plt otp.plt --src src          # prints the warning, exits 2
dialyzer --plt otp.plt --src --raw src    # crashes
```

The first command prints a page of warnings about OTP itself and may exit
non-zero; what matters is that `otp.plt` exists afterwards.

## The module

`src/m.erl` is the shortest module that makes Dialyzer warn with no flags:

```erlang
-module(m).
-export([g/0]).

f() -> erlang:error(bad).

g() -> f().
```

`f/0` always raises, so `g/0` can never return normally, and Dialyzer says so.
Nothing about the crash depends on which warning it is: it was first seen on a
`pattern_match_cov` warning, and `set_warning_id/2` is called on every warning
`--raw` is about to print.

## What was ruled out

- **Not the output file.** `--raw` crashes the same way with no `-o` at all and
  with `-o raw.txt`, which is left empty. The ordinary run with `-o plain.txt`
  writes the warning to the file and exits 2.
- **Not one release.** The same `./run.sh`, with `devbox.json` pointed at each
  package in turn, reproduces on OTP 26 (Dialyzer 5.1.3), 27 (5.3), 28 (5.4)
  and 29.0-rc1 (6.0) — each the newest devbox has of that release.
- **Not a warning-free run.** With nothing to report, `--raw` exits 0 and
  prints `done (passed successfully)`, which is why a clean codebase never sees
  this.
