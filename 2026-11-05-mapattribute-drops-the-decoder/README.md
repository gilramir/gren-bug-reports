# `Html.Attributes.map` loses an event handler's decoder, so the event throws

Against `gren` 0.6.6, `gren-lang/browser` 6.0.2, `gren-lang/core` 7.4.2;
Chromium 1248 (Playwright 1.64.1). Still in `gren-lang/browser`'s `main` at
`2c8c8fb`.

`./run.sh` builds `index.html` under `devbox`. The page has two buttons, each
with `Html.Events.onClick Clicked`; the second's attribute is put through
`Html.Attributes.map Wrapped`. The page lists every message `update` gets.

| click | messages | console |
|---|---|---|
| `plain` | `Clicked` | — |
| `mapped` | none (expected `Wrapped Clicked`) | `Uncaught TypeError: Cannot read properties of undefined (reading '$')` |

`_VirtualDom_mapHandler` in `src/Gren/Kernel/VirtualDom.js` computes the
mapped decoder in each case of its `switch` and throws it away:

```js
var mappedDecoder;
switch (tag) {
  case 0:
    A2(__Json_map, func, handler.a);
    break;
  ...
}
return { $: handler.$, a: mappedDecoder };
```

so the handler it returns has `a: undefined`, and the click's
`_Json_runHelp(handler.a, event)` reads `undefined.$`. Elm's version returned
the decoder from one expression; the `switch` came with `8a5d366`
("Incorporate VirtualDom, Html and Svg packages", 2022).

The fix is `mappedDecoder = ` before each of the four calls.

`Html.map` is not affected: it wraps the node in a tagger and never maps a
handler. `Html.Attributes.map` and `VirtualDom.mapAttribute` are the two ways
in.
