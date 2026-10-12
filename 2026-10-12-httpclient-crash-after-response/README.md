# A crash after `HttpClient.send` answers is lost

**Repository:** `gren-lang/node`
**Found against:** `gren` 0.6.6, `gren-lang/core` 7.6.0, `gren-lang/node` 6.2.0, node 22

`./run.sh` builds and runs `src/Main.gren` under `devbox`. The program sends a
request to a `data:` URL, so no network is needed, and the task that continues
the response is a `Debug.todo`. It should end the program with the `TODO`
message. It prints nothing:

```
exit status: 0
```

With the request taken out, so that the same `Debug.todo` continues
`Task.succeed {}`, the program prints

```
Error: TODO in module `Main` on line 19

after the response
```
