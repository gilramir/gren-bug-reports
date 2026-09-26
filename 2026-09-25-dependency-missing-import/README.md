# A dependency that fails to build is reported as version 1.0.0, with no cause

`lib` is a package at version 3.2.1 whose one module imports a module that
does not exist. `app` depends on it with `local:../lib`.

```console
$ cd app && gren make Main --output=/dev/null
```

The report names `example/lib 1.0.0`, guesses that "it has package
constraints that are too wide", and ends its note with an empty block. It
never says that `Lib` imports `Missing`, and the version is not the package's.
