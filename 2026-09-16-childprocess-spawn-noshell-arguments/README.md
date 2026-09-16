# `ChildProcess.spawn` with `NoShell` looks for a program named after the program and its arguments

`gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22, Linux x86-64.

## Summary

`ChildProcess.spawn` with `shell = NoShell` works for a program with no
arguments, and fails for any program given arguments. `spawn permission "test"
[ "1", "-eq", "1" ]` does not run `test`: node is asked for a program whose name
is `test 1 -eq 1`, which does not exist.

| spawn | exit code | expected |
|---|---|---|
| `DefaultShell`, `true`, no arguments | 0 | 0 |
| `DefaultShell`, `test`, `["1", "-eq", "1"]` | 0 | 0 |
| `NoShell`, `true`, no arguments | 0 | 0 |
| `NoShell`, `test`, `["1", "-eq", "1"]` | **the program crashes**: `Error: spawn test 1 -eq 1 ENOENT` | 0 |

The last row crashes, where you would expect a failure to reach `onExit`.
That crash is a second defect, reported separately. With the arguments passed
correctly, this row would reach `onExit` with 0.

The cause is in `Gren/Kernel/ChildProcess.js`. Since 6833e85 ("Fix deprecation
warning when spawning child processes"), the program and its arguments are
joined into one string before `spawn` is called, whatever the shell option is:

```js
var cmd = [options.__$program].concat(options.__$arguments).join(" ");

var subproc = childProcess.spawn(cmd, {
  // ...
  shell: _ChildProcess_handleShell(shell),
```

With a shell, the shell splits that string again, which is what the deprecation
warning asked for. Without a shell, node treats the whole string as the file to
run.

## Reproduction

```
$ node app
| spawn | exit code | expected |
|---|---|---|
| DefaultShell, true, no arguments | 0 | 0 |
| DefaultShell, test, ["1", "-eq", "1"] | 0 | 0 |
| NoShell, true, no arguments | 0 | 0 |
node:events:497
      throw er; // Unhandled 'error' event
      ^

Error: spawn test 1 -eq 1 ENOENT
```

## The fix

Join only when there is a shell to split the string again:

```js
var shellOption = _ChildProcess_handleShell(shell);

var subproc = shellOption
  ? childProcess.spawn(
      [options.__$program].concat(options.__$arguments).join(" "),
      { /* options, with shell: shellOption */ },
    )
  : childProcess.spawn(options.__$program, options.__$arguments, {
      /* options, with shell: false */
    });
```

---

- **Filed as:** not yet filed
- **Package:** `gren-lang/node`
- **Versions:** `gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22
