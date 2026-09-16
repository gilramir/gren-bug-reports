# `FileSystem.Lock` reports `UnexpectedError ENOENT` when the lock is released while it checks it

`aquire` creates the lock directory. If that fails because the directory exists,
it reads the directory's metadata, to see whether the lock is stale. If the
other process removes the lock between those two steps, `metadata` fails with
`ENOENT`. The handler for that failure means to try again:

```gren
LockMetaCheck { path, attempt, result = Err fsErr } ->
    if FileSystem.errorIsFileExists fsErr then
        -- Lock might have been removed while we asked for metadata
        update fsPerm (Lock { path = fromLockPath path, attempt = attempt + 1 }) model

    else
        UnexpectedError { path = fromLockPath path, error = fsErr }
```

but it tests for `EEXIST`, which reading metadata never fails with, so the
attempt ends as `UnexpectedError`.

## Reproduction

`churn.js` creates and removes `.lock` in a tight loop, standing in for another
process that holds the lock very briefly. `src/Main.gren` tries to take the lock
2000 times, without retries, releasing it whenever it gets it, and counts how
each attempt ended. Every attempt should end as `lock acquired` or
`already locked`.

```
$ ./run.sh
$ node app
outcome                      count
UnexpectedError ENOENT         929
already locked                 232
lock acquired                  839
```

The counts depend on timing and vary between runs.

## The fix

```gren
if FileSystem.errorIsNoSuchFileOrDirectory fsErr then
```

With it, the same program gave 325 `already locked` and 1675 `lock acquired`.

- **Filed as:** not yet filed
- **Package:** `gren-lang/compiler-node` 5.0.0
- **Versions:** `gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22
