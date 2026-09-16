# `ChildProcess.spawn` crashes the program when the program to spawn cannot be started

`gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22, Linux x86-64.

## Summary

A `ChildProcess.spawn` whose program cannot be started, such as a program that
does not exist or a file that is not executable, run with `NoShell`, ends the
whole Gren program with node's `Unhandled 'error' event`. Neither of the
command's messages arrives, and the application cannot handle the failure.

| spawn | exit code | expected |
|---|---|---|
| `DefaultShell`, `no-such-program` | 127 | non-zero |
| `NoShell`, `no-such-program` | **the program crashes**: `Error: spawn no-such-program ENOENT` | non-zero |

With a shell, the shell starts, fails to find the program, and exits 127, so
`onExit` receives it. Without one, node reports the failure asynchronously, as
an `error` event on the `ChildProcess`, and `Gren/Kernel/ChildProcess.js`
installs no listener for it. An `error` event with no listener throws.

The kernel already has an answer for a spawn that fails synchronously, which is
to send `onExit` the error's `errno`:

```js
} catch (e) {
  callback(
    __Scheduler_succeed(
      __Scheduler_rawSpawn(
        sendExitToApp(typeof e.errno === "undefined" ? -1 : e.errno),
      ),
    ),
  );
```

The asynchronous failure, which is how node reports a missing program,
never gets there.

## Reproduction

```
$ node app
| spawn | exit code | expected |
|---|---|---|
| DefaultShell, no-such-program | 127 | non-zero |
node:events:497
      throw er; // Unhandled 'error' event
      ^

Error: spawn no-such-program ENOENT
```

## The fix

Listen for the event, and report it as the synchronous failure is reported:

```js
subproc.on("error", function (e) {
  __Scheduler_rawSpawn(
    sendExitToApp(typeof e.errno === "undefined" ? -1 : e.errno),
  );
});
```

If the process never started, `exit` does not follow the `error` event, so
`onExit` is sent once. An `error` after the process has started, such as a
failed `kill`, can be followed by `exit`, so a complete fix sends `onExit` for
an `error` only if no `exit` has arrived.

---

- **Filed as:** not yet filed
- **Package:** `gren-lang/node`
- **Versions:** `gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22
