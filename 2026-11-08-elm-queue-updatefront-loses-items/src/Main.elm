module Main exposing (main)

import Queue


main : Program () () ()
main =
    let
        q =
            Queue.singleton 3
                |> Queue.enqueue 4
                |> Queue.updateFront (\_ -> Nothing)

        _ =
            Debug.log "toList" (Queue.toList q)

        _ =
            Debug.log "size" (Queue.size q)

        _ =
            Debug.log "front" (Queue.front q)

        _ =
            Debug.log "Tuple.first (dequeue q)" (Tuple.first (Queue.dequeue q))

        _ =
            Debug.log "toList (Tuple.second (dequeue q))" (Queue.toList (Tuple.second (Queue.dequeue q)))
    in
    Platform.worker
        { init = \_ -> ( (), Cmd.none )
        , update = \_ _ -> ( (), Cmd.none )
        , subscriptions = \_ -> Sub.none
        }
