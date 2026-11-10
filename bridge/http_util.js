// The bridge's HTTP helpers, shared by server.js and the route modules: a JSON
// answer (json), a request's JSON body (body) and its raw bytes (bytes). Both
// JSON ways speak the player's names (names.js): shown going out, turned back
// coming in. Moved verbatim from server.js (consolidation C3, step 8).

import * as names from "./names.js";

export function json(res, code, body) {
  res.writeHead(code, { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" });
  res.end(JSON.stringify(names.showAll(body)));  // in the player's names (names.js)
}

export function body(req) {
  return new Promise((resolve) => {
    let b = "";
    req.on("data", (d) => (b += d));
    req.on("end", () => { try { resolve(names.innerAll(JSON.parse(b || "{}"))); } catch { resolve({}); } });  // the player's names, turned back
  });
}

export function bytes(req) {
  return new Promise((resolve) => {
    const parts = [];
    req.on("data", (d) => parts.push(d));
    req.on("end", () => resolve(Buffer.concat(parts)));
  });
}
