# A report with no path runs its title into the dashes

`Cli.Report.toString` pads a report's header to 80 columns with dashes. With a
path it writes a space, the dashes, a space and the path. Without one it writes
the dashes straight after the title:

```
$ ./run.sh
-- INCOMPATIBLE PACKAGE--------------------------------------------------------|
```

The compiler's own reports, which the Haskell backend renders, put a space
there: `-- TYPE MISMATCH ---------- src/Main.gren`.

Found against `gren` 0.6.6 and `gren-lang/compiler-node` 5.0.0.
