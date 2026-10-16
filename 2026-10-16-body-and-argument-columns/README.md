# A body and its arguments are measured from the wrong column

**Repository:** `gren-lang/compiler-common`
**Found against:** `gren` 0.6.6, `gren-lang/compiler-common` `main` at
`d8dedc6`, `gren-lang/core` 7.6.0, `gren-lang/node` 6.2.0, node 22

`./run.sh` fetches `compiler-common` at `d8dedc6` and builds and runs
`src/Main.gren` under `devbox`. Each row is a module given to
`Compiler.Parse.Module.parser`, beside what `gren make` does with the same
module:

```
	gren make	compiler-common
argument left of its function, top level	compiles	refused
argument left of its function, in a let	compiles	refused
argument left of its function, in a branch	compiles	refused
body at its name's column, on the let's row	refuses	parses
body left of its name, on the let's row	refuses	parses
destructuring's body left of its pattern	refuses	parses
destructuring's body at its pattern's column	refuses	parses
```

The first three rows are refused at `e4d61ec`, before #14's fix, as well.
