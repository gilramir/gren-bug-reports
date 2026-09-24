# A report with no path is printed with its title run into the dashes

**Repository:** `gren-lang/compiler-node`
**Found against:** `gren` 0.6.6, `gren-lang/compiler-node` 5.0.0, node 22

`Cli.Report.toString` puts a space between the title and the dashes when the
report has a path, and none when it has no path, so every path-less report the
CLI prints (`INCOMPATIBLE PACKAGE`, `PROBLEM INSTALLING PACKAGE`, `CANNOT FIND
COMPATIBLE VERSION`, ...) reads `-- TITLE-----`. The compiler's own reports have
the space.

| | header |
|---|---|
| printed | `-- INCOMPATIBLE PACKAGE--------------------------------------------------------` |
| expected | `-- INCOMPATIBLE PACKAGE -------------------------------------------------------` |

## Reproduction

`./run.sh` does all of this, using the `gren` and `node` that devbox pins.

A node application that lists `gren-lang/browser`:

```json
{
 "type": "application",
 "platform": "node",
 "source-directories": ["src"],
 "gren-version": "0.6.6",
 "dependencies": {"direct": {"gren-lang/core": "7.4.2", "gren-lang/browser": "6.0.0"}, "indirect": {"gren-lang/url": "6.0.0"}}
}
```

`src/Main.gren`:

```gren
module Main exposing (main)

import Node

main = Node.defineSimpleProgram (\_ -> Node.endSimpleProgram (Node.startProgram {}))
```

Output:

```
$ gren make Main --output=/dev/null
-- INCOMPATIBLE PACKAGE--------------------------------------------------------

gren-lang/browser targets the browser platform.

However, the current project targets the node, which is not compatible.
```

## Cause

In `src/Cli/Report.gren`, the `Just path` branch of `errorBarEnd` writes
`" " ++ makeDashes (5 + ...) ++ " " ++ pathStr`, and the `Nothing` branch writes
`makeDashes (4 + String.unitLength title)` with no space.

## Fix

```gren
Nothing ->
    " " ++ makeDashes (5 + String.unitLength title)
```

The report's second sentence also lacks a word: "targets the node" should be
"targets the node platform".
