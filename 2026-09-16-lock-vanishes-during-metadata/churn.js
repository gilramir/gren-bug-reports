// Create and remove ./.lock in a tight loop, as another process holding the
// lock very briefly would.
const fs = require("node:fs");
for (;;) {
  try { fs.mkdirSync(".lock"); } catch (e) {}
  try { fs.rmdirSync(".lock"); } catch (e) {}
}
