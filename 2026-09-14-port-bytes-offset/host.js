// The host. It sends the program the bytes [4, 5] three ways, receives the
// program's 3-byte body two ways, and prints what each side saw.

const path = require("node:path");
const { Gren } = require(path.resolve("main.js"));

const describe = (view) => {
  const ints = Array.from(new Uint8Array(view.buffer, view.byteOffset, view.byteLength));
  const shown = ints.length <= 8 ? ints.join(", ") : ints.slice(0, 5).join(", ") + ", ...";
  return `${view.byteLength} bytes [${shown}]`;
};

// [4, 5], as a view into a larger buffer: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9].
const view = () => new DataView(new Uint8Array([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]).buffer, 4, 2);

// [4, 5], as a Node Buffer. Node allocates small Buffers out of a shared 8 KiB pool.
const nodeBuffer = Buffer.from([4, 5]);
const fromBuffer = new DataView(nodeBuffer.buffer, nodeBuffer.byteOffset, nodeBuffer.byteLength);

const seen = {};

const app = Gren.Main.init({
  flags: view(),
  taskPorts: {
    roundTrip: async (input) => {
      seen["roundTrip input"] = describe(input);
      return view();
    },
  },
});

app.ports.report.subscribe(({ label, bytes }) => {
  seen[label] = seen[label] ? [seen[label], bytes] : bytes;
});

app.ports.toHost.subscribe((bytes) => {
  seen["toHost"] = describe(bytes);
  app.ports.fromHost.send(view());
  app.ports.fromHost.send(fromBuffer);
});

setTimeout(() => {
  const rows = [
    ["program -> host", "toHost body", seen["toHost"], "3 bytes [7, 8, 9]"],
    ["program -> host", "roundTrip body (input)", seen["roundTrip input"], "3 bytes [7, 8, 9]"],
    ["host -> program", "flags: a view of [4, 5]", seen["flags"], "2 bytes [4, 5]"],
    ["host -> program", "roundTrip result: a view of [4, 5]", seen["roundTrip result"], "2 bytes [4, 5]"],
    ["host -> program", "fromHost: a view of [4, 5]", (seen["fromHost"] || [])[0], "2 bytes [4, 5]"],
    ["host -> program", "fromHost: Buffer.from([4, 5])", (seen["fromHost"] || [])[1], "2 bytes [4, 5]"],
  ];
  const widths = [15, 36, 30];
  const line = (cells) => cells.map((c, i) => (i < 3 ? String(c).padEnd(widths[i]) : c)).join("  ");
  console.log(line(["direction", "port", "received", "expected"]));
  for (const row of rows) console.log(line(row));
  process.exit(0);
}, 200);
