# `Queue.updateFront` that drops the front's only item leaves the rest unreachable

Against `gren` 0.6.6, `gren-lang/test` 5.0.0, `gren-lang/core` 7.4.2,
`gren-lang/node` 6.1.3, node 22.

`./run.sh` builds and runs `src/Main.gren`, a program over `gren-lang/test`'s
internal `Queue` module. `src/Queue.gren` is that module copied unchanged from
the published `gren-lang/test` 5.0.0, since it is not exposed. It prints:

| on `singleton 3 \|> enqueue 4 \|> updateFront (\_ -> Nothing)` | result | expected |
|---|---|---|
| `toArray` | `[4]` | `[4]` |
| `size` | `1` | `1` |
| `front` | `Nothing` | `Just 4` |
| `(dequeue q).first` | `Nothing` | `Just 4` |
| `toArray (dequeue q).rest` | `[]` | `[]` |

`Queue` keeps a front and a rear array, and its functions rely on the front
being empty only when the rear is too: `front` answers `Array.first q.front`,
and `dequeue` answers `Nothing` when the front has nothing to pop. Every
function that builds a queue goes through the private `queue`
pseudo-constructor, which moves the rear to the front when the front is
empty — except `updateFront`, which builds
`Queue { front = update_ (Just h) t, rear = q.rear }` directly. When its
function answers `Nothing` for a front of one item, the result has an empty
front and a non-empty rear, so `toArray` and `size` still count the 4 but
`front` and `dequeue` cannot reach it.

`Queue` is not an exposed module and nothing in the package calls
`updateFront` today, so the defect is latent.

The fix is to build both of `updateFront`'s results with
`queue (update_ ...) q.rear` instead of `Queue { front = ..., rear = q.rear }`.
