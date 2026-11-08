# `Queue.updateFront` that drops the front's only item leaves the rest unreachable

Against `turboMaCk/queue` 1.2.0 (`master` at `c6605fd`), `elm/core` 1.0.5,
`elm` 0.19.1, node 22.

`./run.sh` builds `src/Main.elm` and runs it under node; it prints, with
`Debug.log`:

| on `singleton 3 \|> enqueue 4 \|> updateFront (\_ -> Nothing)` | result | expected |
|---|---|---|
| `toList` | `[4]` | `[4]` |
| `size` | `1` | `1` |
| `front` | `Nothing` | `Just 4` |
| `Tuple.first (dequeue q)` | `Nothing` | `Just 4` |
| `toList (Tuple.second (dequeue q))` | `[]` | `[]` |

`Queue` keeps a front and a rear list, and its functions rely on the front
being empty only when the rear is too: `front` answers `List.head fl`, and
`dequeue` answers `Nothing` when `fl` is `[]`. Every function that builds a
queue goes through the private `queue` function, which moves the rear to the
front when the front is empty, except `updateFront`, which builds
`Queue (update_ (Just h) t) rl` directly. When its function answers
`Nothing` for a front of one item, the result is `Queue [] [4]`: `toList`
and `size` still count the 4, but `front` and `dequeue` cannot reach it.

The fix is to build both of `updateFront`'s results with `queue` instead of
`Queue`.
