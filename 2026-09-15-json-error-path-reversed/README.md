# `Json.Decode.errorToString` writes the path to a failure backwards

## Summary

`errorToString` names where a decoder failed as a path from the root,
`json.user.address.city`. Any path of two or more steps comes out in reverse,
`json.city.address.user`, so the message points at a place that is not in the
value, or at a different element than the one that failed. A path that happens
to read the same both ways, such as `[1][1]`, hides it.

## Reproduction

`./run.sh` prints the table, showing the first line of each message.

| call | result | expected |
|---|---|---|
| `field "a" int`, on `{"a":true}` | Problem with the value at json.a: | Problem with the value at json.a: |
| `at ["user", "address", "city"] string`, on `{"user":{"address":{"city":1}}}` | Problem with the value at json.city.address.user: | Problem with the value at json.user.address.city: |
| `field "items" (array (field "id" int))`, on `{"items":[{"id":1},{"id":null}]}` | Problem with the value at json.id[1].items: | Problem with the value at json.items[1].id: |
| `array (array int)`, on `[[1,2,3],[4,true]]` | Problem with the value at json[1][1]: | Problem with the value at json[1][1]: |
| `array (array int)`, on `[[1,2],[3,4],[true]]` | Problem with the value at json[0][2]: | Problem with the value at json[2][0]: |

The `Error` value itself is right: `Field { name = "user", error = Field { name = "address", ... } }`.
Only the text is reversed. The same reversed path appears in
"The Json.Decode.oneOf at json… failed" and in "Ran into a Json.Decode.oneOf
with no possibilities at json…".

## Cause and fix

`errorToStringHelp` in `src/Json/Decode.gren` walks the error from the outside
in and puts each step in front of the steps it has already seen:

```gren
errorToStringHelp err ([ fieldName ] ++ context)
...
errorToStringHelp err ([ indexName ] ++ context)
```

This is `elm/json`'s `fieldName :: context`, but `elm/json` reverses the list
before joining it (`String.join "" (List.reverse context)`, three times), and
the port kept the prepend and dropped the reverse. With an `Array`, appending is
the natural fix, and the three joins stay as they are:

```gren
errorToStringHelp err (context ++ [ fieldName ])
...
errorToStringHelp err (context ++ [ indexName ])
```

- **Filed as:** not yet filed
- **Package:** `gren-lang/core` 7.4.2, and `main` as of 2026-09-15
- **Versions:** `gren` 0.6.6, node 22
