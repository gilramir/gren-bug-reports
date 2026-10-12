#!/usr/bin/env python3
"""gen.py SHAPE N: writes src/Main.gren and src/Big.gren, where Big is
N of SHAPE and Main prints one value from it."""
import sys

shape, n = sys.argv[1], int(sys.argv[2])

if shape == "declarations":
    # N top-level values, and one more that adds two of them.
    body = "value : Int\nvalue =\n    x0 + x{}\n\n\n".format(n - 1) + "\n\n\n".join(f"x{k} : Int\nx{k} =\n    {k}" for k in range(n))
elif shape == "functions":
    # N top-level functions of one argument, each calling the one before.
    fns = "\n\n\n".join(f"f{k} : Int -> Int\nf{k} a =\n    {'a' if k == 0 else f'f{k - 1} a + 1'}" for k in range(n))
    body = f"value : Int\nvalue =\n    f{n - 1} 0\n\n\n{fns}"
elif shape == "let":
    # One let of N bindings, each the one before plus one.
    lets = "\n\n".join(f"        x{k} =\n            {'0' if k == 0 else f'x{k - 1} + 1'}" for k in range(n))
    body = f"value : Int\nvalue =\n    let\n{lets}\n    in\n    x{n - 1}"
else:
    sys.exit(f"unknown shape {shape}")

open("src/Big.gren", "w").write(f"module Big exposing (value)\n\n\n{body}\n")
open("src/Main.gren", "w").write("""module Main exposing (main)

import Big
import Node
import Stream
import Task


main : Node.SimpleProgram a
main =
    Node.defineSimpleProgram <| \\env ->
        Node.endSimpleProgram
            (Stream.writeLineAsBytes (String.fromInt Big.value) env.stdout
                |> Task.map (\\_ -> {})
                |> Task.onError (\\_ -> Task.succeed {})
            )
""")
