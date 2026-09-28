// Answers every request with a Date header, as any server does, and two
// cookies, the first with an Expires attribute. Prints its port and waits.
import http from "node:http";

const server = http.createServer((req, res) => {
  res.setHeader("date", "Mon, 28 Sep 2026 12:00:00 GMT");
  res.setHeader("set-cookie", [
    "a=1; Expires=Wed, 21 Oct 2026 07:28:00 GMT",
    "b=2",
  ]);
  res.end("ok");
});

server.listen(0, "127.0.0.1", () => console.log(server.address().port));
