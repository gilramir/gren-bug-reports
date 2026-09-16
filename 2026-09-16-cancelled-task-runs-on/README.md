# A cancelled task keeps running once the operation it was waiting on finishes

`Process.kill` and `Task.concurrent`'s cancellation of its other tasks both stop
a process by clearing the task it is waiting on and calling that operation's
cancel function, if it has one. Most operations do not have one. When such an
operation finishes, its callback sets the process's task again and puts the
process back on the queue, so the cancelled process carries on from where it
was stopped:

```js
} else if (rootTag === __1_BINDING) {
  proc.__root.__kill = proc.__root.__callback(function (newRoot) {
    proc.__root = newRoot;          // runs even after rawKill set __root to null
    _Scheduler_enqueue(proc);
  });
  return;
}
```

## Reproduction

`src/Main.gren` cancels a task twice while it waits on `FileSystem.readFile`,
which has no cancel function: once with `Process.kill`, and once by failing the
other task in a `Task.concurrent`. After each, the cancelled task prints a line.
Neither line should appear.

```
$ ./run.sh
$ node app
1. Process.kill
   killed
   the killed process ran on
2. Task.concurrent
   concurrent failed: the other task failed
   the cancelled sibling ran on
done
```

## The fix

Ignore a callback for a binding the process is no longer waiting on:

```js
} else if (rootTag === __1_BINDING) {
  var binding = proc.__root;
  binding.__kill = binding.__callback(function (newRoot) {
    if (proc.__root !== binding) {
      return;
    }
    proc.__root = newRoot;
    _Scheduler_enqueue(proc);
  });
  return;
}
```

With this patched into `app`, the same program printed neither line.

- **Filed as:** not yet filed
- **Package:** `gren-lang/core` 7.4.2
- **Versions:** `gren` 0.6.6, `gren-lang/node` 6.1.3, node 22
