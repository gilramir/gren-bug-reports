#!/usr/bin/env python3
"""gen.py SHAPE N: writes src/Main.gren and src/Big.gren, where Big is
N of SHAPE and Main prints one value from it."""
import sys

shape, n = sys.argv[1], int(sys.argv[2])

if shape == "when-int":
    # A when of N Int branches and a wildcard.
    branches = "\n\n".join(f"        {k} ->\n            {k + 1}" for k in range(n))
    body = f"value : Int\nvalue =\n    pick 3\n\n\npick : Int -> Int\npick k =\n    when k is\n{branches}\n\n        _ ->\n            0"
elif shape == "variants":
    # A custom type of N variants, and nothing that matches on it.
    ctors = "\n".join(("    = " if k == 0 else "    | ") + f"C{k}" for k in range(n))
    body = f"type T\n{ctors}\n\n\nvalue : Int\nvalue =\n    when C1 is\n        C0 ->\n            0\n\n        _ ->\n            1"
elif shape == "when-variants":
    # The same type and a when over every variant.
    ctors = "\n".join(("    = " if k == 0 else "    | ") + f"C{k}" for k in range(n))
    branches = "\n\n".join(f"        C{k} ->\n            {k}" for k in range(n))
    body = f"type T\n{ctors}\n\n\nvalue : Int\nvalue =\n    toInt C1\n\n\ntoInt : T -> Int\ntoInt t =\n    when t is\n{branches}"
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
