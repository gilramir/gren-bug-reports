# Effect manager state corrupted when `onEffects` uses `Task.map2`/`map3`/`concurrent`

An `HttpServer` program that also holds **any** `Node` subscription crashes on the
second request:

```
TypeError: Cannot read properties of undefined (reading '$')
    at $gren_lang$node$Node$onEffects$
    at A3
    at Object.b                <- the effect manager's `loop` receive callback
    at _Scheduler_step
    at _Scheduler_enqueue
    at _Scheduler_rawSpawn
    at IncomingMessage.<anonymous>
```

`Node.onEffects` is reading `state.emptyEventLoopListener` on a value that is not its
state record.

- **Package:** `gren-lang/core` (kernel scheduler); surfaces through `gren-lang/node`
- **Versions:** gren 0.6.6, gren-lang/core 7.4.2, gren-lang/node 6.1.3, Node.js v25.1.0, Linux x86-64

## Reproducing

```sh
./run.sh
```

That builds and drives two programs. A Control program which works fine, and a
Crash program which crashes. The difference between the 2 programs is minimal.

```
=== Crash (HttpServer + one Node subscription) — expected: dies on request 2
request 1: 204
request 2: 000no response
--- crash.log:
TypeError: Cannot read properties of undefined (reading '$')
...

=== Control (same program, no Node subscription) — expected: all fine
request 1: 204
request 2: 204
request 3: 204
request 4: 204
request 5: 204
```

By hand:

```sh
gren make Crash --output crash
node crash &                                # listens on :8085
curl -s -o /dev/null -w '%{http_code}\n' localhost:8085/   # 204
curl -s -o /dev/null -w '%{http_code}\n' localhost:8085/   # process is dead
```

`src/Crash.gren` is ~65 lines. `src/Control.gren` is the same program with the
`Node.onSignalTerminate` subscription deleted and nothing else changed; it serves
requests indefinitely.

## What the reproduction needs

Three ingredients, each necessary:

1. **the reply goes through a `Task.perform`**, so each request causes two effect
   dispatches instead of one;
2. **the reply carries no body** (`Response.setStatus 204` and nothing else) — this
   is what lines the two dispatches up inside one scheduler drain. Adding
   `Response.setBody "ok"` makes the crash go away;
3. **any `Node` subscription** — `onSignalTerminate`, `onSignalInterrupt` or
   `onEmptyEventLoop`. `Node.onEffects` builds its next state with `Task.map3`.

Ingredient 2 is a timing detail rather than a semantic one: it is one way to land a
message in the manager's mailbox during the window described below. The underlying
race presumably has other triggers.

## Diagnosis

`_Scheduler_step` has no guard against **re-entering a parked binding**
(`gren-lang/core/src/Gren/Kernel/Scheduler.js:191`):

```js
} else if (rootTag === __1_BINDING) {
  proc.__root.__kill = proc.__root.__callback(function (newRoot) {
    proc.__root = newRoot;
    _Scheduler_enqueue(proc);
  });
  return;
}
```

If a process is suspended at a `__1_BINDING` task and is enqueued again for any
reason — `_Scheduler_rawSend` (line 117) does exactly that when it delivers a mailbox
message — `_Scheduler_step` runs the binding's body a *second* time instead of leaving
the process parked.

For most bindings that is merely wasteful. For `_Scheduler_concurrent` (line 52) it
corrupts state: the body spawns a second set of sub-processes, so the binding's
`callback` is eventually invoked **twice**.

- The first invocation sets `proc.__root = succeed(results)` and the process resumes,
  popping the continuation that consumes those results.
- The second invocation sets `proc.__root = succeed(results)` again — but that
  continuation is already gone, so the raw `results` **array** falls through to
  whatever is left on the stack.

In an effect manager the thing left on the stack is `loop`, so the array becomes the
manager's state and the *next* `onEffects` call reads garbage out of it.

`Task.map2` is built on `_Scheduler_concurrent` (line 86):

```js
var _Scheduler_map2 = F3(function (callback, taskA, taskB) {
  function combine([resA, resB]) { return _Scheduler_succeed(A2(callback, resA, resB)); }
  return A2(_Scheduler_andThen, combine, _Scheduler_concurrent([taskA, taskB]));
});
```

so `map2`, `map3`, `andMap` and everything derived from them are exposed. Any effect
manager whose `onEffects` returns one of those is affected; `Node.onEffects` ends in
`Task.map3` over its three listener tasks, which is why this reproduction needs a
`Node` subscription specifically.

## Evidence

Instrumenting the compiled output to log each manager's state on every dispatch, and
to warn when `_Scheduler_step` re-enters an already-entered binding:

```
[dispatch] home=Task procId=0
[dispatch] home=HttpServer procId=1
[dispatch] home=Node procId=2
[dispatch] home=HttpServer.Response procId=3
...
[fx] manager=Node stateKeys=emptyEventLoop,emptyEventLoopListener,signalInterrupt,...  <- healthy
[REENTRY] binding re-entered on proc 2 (mailbox len 1)          <- the Node manager
[REENTRY] binding re-entered on proc 40 (mailbox len 0)         <- sub-procs concurrent spawned
[REENTRY] binding re-entered on proc 44 (mailbox len 0)
[fx] manager=Node stateKeys=emptyEventLoop,...                  <- first callback: correct
[fx] manager=Node stateKeys=0,1                                 <- second callback: the raw
                                                                   2-element results array
                                                                   became the state
TypeError: Cannot read properties of undefined (reading '$')
```

`proc 2` is the `Node` manager. The mailbox length of 1 is the new `fx` message that
arrived while it was parked inside `concurrent`. `stateKeys=0,1` is an `Array` of
length 2 — exactly `_Scheduler_concurrent`'s `results` for a `map2`.

## Candidate fix

Don't re-enter a binding that is already running:

```js
} else if (rootTag === __1_BINDING) {
  if (proc.__root.__entered) { return; }   // added
  proc.__root.__entered = true;            // added
  proc.__root.__kill = proc.__root.__callback(function (newRoot) { ... });
  return;
}
```

Patching the equivalent two lines into the compiled `crash` output makes this
reproduction serve requests indefinitely (6/6 requests, no crash), and also fixes the
real application this was found in.

A proper fix probably wants a "running" flag on the process rather than a property on
the task. It is also worth looking at `proc.__root.__kill = proc.__root.__callback(...)`
on that same line: `proc.__root` is read twice, and the callback may already have
replaced it by the time the assignment happens, so a synchronously-resolving binding
writes `__kill` onto the wrong task object.

## Impact

Any long-lived program that combines an effect manager using `Task.map2`/`map3` in
`onEffects` with frequent effect dispatches. Concretely: a `gren-lang/node` HTTP
server cannot subscribe to `Node.onSignalTerminate`, which is what you need to shut
down cleanly on SIGTERM — the normal requirement for a container under
Kubernetes, where the process is PID 1 and gets no default signal handling.

