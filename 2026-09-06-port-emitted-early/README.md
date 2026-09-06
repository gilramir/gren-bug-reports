# A port's `var` can be emitted before the kernel chunk it calls into

A `port` compiles to a `var` whose initializer calls `_Platform_incomingPort`,
`_Platform_outgoingPort` or `_Platform_taskPort`. All three touch module-level
`var`s that live in the kernel `Platform` chunk — `_Platform_effectManagers` and
`_Platform_taskPorts` — so that chunk has to have been evaluated first.

Nothing makes it be. `Optimize.Module.addPort` records only the *converter's*
dependencies on the port's graph node:

```haskell
-- compiler/src/Optimize/Module.hs
Can.Incoming _ payloadType _ ->
  let (deps, fields, decoder) = Names.run (Port.toDecoder payloadType)
      node = Opt.PortIncoming (Port.isBytes payloadType) decoder deps
   in addToGraph (Opt.Global home name) node fields graph
```

`deps` is what `Json.Decode.string` and friends need. The kernel `Platform`
module — which `Generate.JavaScript.generatePort` is about to emit a call
into — is not in it, so `Generate.JavaScript` is free to emit the port's `var`
above the chunk that defines what the call reads.

Whether it does depends on the rest of the program, because the emission order
is a traversal of the dependency graph and the port is being ordered against
edges it has no place in. When it goes the wrong way the bundle throws while it
is being evaluated, and the program never starts.

## Reproduction

```console
$ ./run.sh
```

That builds `src/Main.gren` with devbox's `gren` and serves this directory.
Open <http://localhost:8000/> and look at the JavaScript console:

```
Uncaught TypeError: can't access property "inp", _Platform_effectManagers is undefined
    <anonymous> main.js:2113
```

The whole program is fifteen lines and has one port in it:

```gren
port module Main exposing (main)

import Platform


port inp : (String -> msg) -> Sub msg


main : Program {} {} String
main =
    Platform.worker
        { init = \_ -> { model = {}, command = Cmd.none }
        , update = \_ model -> { model = model, command = Cmd.none }
        , subscriptions = \_ -> inp identity
        }
```

Three lines of `main.js` tell the story:

| line | |
|---|---|
| 1790 | `var $author$project$Main$inp = _Platform_incomingPort('inp', …)` — runs first |
| 1877 | `var _Platform_effectManagers = {};` — 87 lines too late |
| 2113 | `if (_Platform_effectManagers[name]) {` in `_Platform_checkPortName`, where the read throws |

The `var` at 1877 is hoisted, so `_Platform_effectManagers` exists by the time
line 1790 runs — it just has not been assigned yet, and `undefined[name]`
throws.

The bundle's last statement is the `_Platform_export({…})` that assigns
`window.Gren`, and evaluation never reaches it, so nothing on the page can start
the program. The page's own scripts still run: a classic script's uncaught
exception aborts that script and nothing else.

`--optimize` makes no difference; the graph is the same. `node -e
"require('./main.js')"` fails identically, at the same line, if that is easier
to look at than a browser console.

Serve the directory rather than opening `index.html` directly — over `file://`
a browser treats every file as its own origin and reports the error as a bare
`Script error.` with no message and no line number.

## What does *not* reproduce it

The order is a traversal of the whole program's graph, so a bigger program is
likely to reach the kernel chunk down some other edge first and come out in the
working order. Three that do:

- the same program with an outgoing port instead — `port out : String -> Cmd
  msg`, sent from `init`;
- a program with several ports in it;
- **the same port on the `node` platform.** `Node.defineProgram` reaches a great
  deal of `gren-lang/core` and `gren-lang/node` before it reaches the port, and
  the chunk comes out first by a wide margin — `var _Platform_effectManagers =
  {}` at line 667 against the port's `var` at 3185.

That last one is why this reproduction is a `browser` application. It is not a
browser-specific bug — nothing here touches the DOM, and `Platform.worker` is
`gren-lang/core`'s — it is that a program small enough to trip the ordering is
only reachable on the platform where `Platform.worker` is the entry point.

Which way the order comes out is not the port's to choose either way, which is
the bug.

## The fix

Record the kernel module the generated call lands in, alongside the converter's
dependencies. In `compiler/src/Optimize/Module.hs`:

```haskell
withPlatform :: Set.Set Opt.Global -> Set.Set Opt.Global
withPlatform = Set.insert (Opt.toKernelGlobal Name.platform)
```

and wrap the `deps` of all four `addPort` branches in it. With that edge in the
graph the chunk is emitted first and the reproduction above loads and runs.

`Opt.Manager` has the same shape of omission — `generateManager` emits calls to
`_Platform_leaf` and `_Platform_createManager`, and assigns into
`_Platform_effectManagers[…]`, and the node carries no dependency on the kernel
`Platform` module either. It has not been observed to misorder, because a
manager is only ever reached through `gren-lang/core` code that names that
module anyway, but the edge is missing there for the same reason and adding it
would cost nothing.

---

- **Filed as:** not yet filed
- **Package:** `gren-lang/compiler`
- **Versions:** gren 0.6.6, gren-lang/core 7.4.2, Firefox 153, Node.js v22.23.2,
  Linux x86-64
