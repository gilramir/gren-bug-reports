#!/usr/bin/env python3
"""gen.py SHAPE N: writes src/Main.gren, a program whose `value` is one
expression of SHAPE, N deep, and which prints it."""
import sys

shape, n = sys.argv[1], int(sys.argv[2])

if shape == "else-if":
    lines = ["value : Int", "value =", "    pick 3", "", "", "pick : Int -> Int", "pick k ="]
    lines.append("    if k == 0 then\n        0\n")
    for i in range(1, n):
        lines.append(f"    else if k == {i} then\n        {i}\n")
    lines.append("    else\n        -1")
    body = "\n".join(lines)
elif shape == "plus":
    body = "value : Int\nvalue =\n    0\n" + "".join(f"        + {i}\n" for i in range(1, n))
elif shape == "pipe":
    body = "value : Int\nvalue =\n    0\n" + "".join("        |> inc\n" for _ in range(1, n)) + "\n\ninc : Int -> Int\ninc x =\n    x + 1\n"
elif shape == "list":
    body = "value : Int\nvalue =\n    Array.length (" + "[ " * n + "1" + " ]" * n + ")\n"
elif shape == "just":
    body = "value : Int\nvalue =\n    when " + "Just (" * (n - 1) + "Just 1" + ")" * (n - 1) + " is\n        _ ->\n            1\n"
else:
    sys.exit(f"unknown shape {shape}")

open("src/Main.gren", "w").write(f"""module Main exposing (main)

import Node
import Stream
import Task


main : Node.SimpleProgram a
main =
    Node.defineSimpleProgram <| \\env ->
        Node.endSimpleProgram
            (Stream.writeLineAsBytes (String.fromInt value) env.stdout
                |> Task.map (\\_ -> {{}})
                |> Task.onError (\\_ -> Task.succeed {{}})
            )


{body}
""")
