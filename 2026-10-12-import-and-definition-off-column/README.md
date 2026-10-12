# An `import`, or a definition under its annotation, is accepted at any column

**Repository:** `gren-lang/compiler-common`
**Found against:** `gren` 0.6.6, `gren-lang/compiler-common` 3.0.0 (and `main` at
`e4d61ec`), `gren-lang/core` 7.6.0, `gren-lang/node` 6.2.0, node 22

`./run.sh` builds and runs `src/Main.gren` under `devbox`. Each row is a module
given to `Compiler.Parse.Module.parser`, and whether it parses. `gren make`
compiles the first row and the sixth, and refuses every other:

```
import at column 1	parses
import at column 3	parses
second import at column 4	parses
import after a block comment	parses
declaration at column 3	parses
definition under its annotation	parses
definition at column 3 under its annotation	parses
definition after a block comment	parses
let definition after a block comment	parses
```

On `main` at `e4d61ec`, which has the fix for #37, the fifth row is refused with
`ExpectedColumnOne`, and the others are as above.
