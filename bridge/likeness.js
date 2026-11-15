// A person's own portrait from the player's photo (Mac 2026-11-15: "a user can add their photo, with OGAD it should be
// converted into the 900AD theme ... if not its just as is"). The photo goes to Off Grid AI Desktop's image model
// (claude.js imageModel; OpenAI's POST /v1/images/edits, the photo as the reference) with the one painted-face style
// (realm/tools/portraits/style.md, the prompt every face of the realm was painted with). Painted, it is that person's
// portrait; with no gateway or image model, or a failed call, the photo itself is (Mac's call). Kept in the reign's
// state/portraits/<id>.<png|jpg>; the view lays it over the dealt face (painted_faces.gd own) on every screen.
// Painting runs off the request: POST answers at once, GET /portraits says who is still being painted.
import fs from "node:fs";
import path from "node:path";
import { imageModel } from "./claude.js";

const STYLE = (() => {
  try {
    const md = fs.readFileSync(new URL("../realm/tools/portraits/style.md", import.meta.url), "utf8");
    return (md.match(/```\n([\s\S]*?)```/)?.[1] ?? "").replace(/\s*\n\s*/g, " ").trim();
  } catch { return ""; }
})();
const painting = new Set();  // ids being painted now
const ID = /^[a-z]?\d+$/i;  // a character (c12) or a royal (r1)

const dir = (ctx) => path.join(ctx.P.state, "portraits");
const fileOf = (ctx, id) => ["png", "jpg"].map((e) => path.join(dir(ctx), `${id}.${e}`)).find((f) => fs.existsSync(f)) ?? null;

// Keep one picture for id (replacing any other kind it had).
function keep(ctx, id, bytes, ext) {
  fs.mkdirSync(dir(ctx), { recursive: true });
  for (const e of ["png", "jpg"]) fs.rmSync(path.join(dir(ctx), `${id}.${e}`), { force: true });
  fs.writeFileSync(path.join(dir(ctx), `${id}.${ext}`), bytes);
}

// The photo painted in the realm's style: the painted PNG's bytes, or null.
async function paint(bytes, ext, subject) {
  const g = await imageModel();
  if (!g || !STYLE) return null;
  const form = new FormData();
  form.append("model", g.model);
  form.append("prompt", STYLE.replace("{subject}", subject));
  form.append("image", new Blob([bytes], { type: ext === "png" ? "image/png" : "image/jpeg" }), `photo.${ext}`);
  form.append("size", "768x1024");
  form.append("response_format", "b64_json");
  const r = await fetch(`${g.base}/images/edits`, { method: "POST", body: form, signal: AbortSignal.timeout(10 * 60 * 1000) });
  if (!r.ok) throw new Error(`images/edits ${r.status}: ${(await r.text()).slice(0, 200)}`);
  const d = (await r.json()).data?.[0] ?? {};
  if (d.b64_json) return Buffer.from(d.b64_json, "base64");
  if (d.url) return Buffer.from(await (await fetch(d.url)).arrayBuffer());
  return null;
}

// POST /portrait?id=&ext=png|jpg&who=, the photo's bytes as the body: answered at once (202), painted after.
export async function add(ctx, req, res, url) {
  const id = String(url.searchParams.get("id") ?? "");
  const ext = url.searchParams.get("ext") === "png" ? "png" : "jpg";
  if (!ID.test(id)) return send(res, 400, { error: "no such person" });
  const chunks = [];
  for await (const c of req) chunks.push(c);
  const bytes = Buffer.concat(chunks);
  if (bytes.length < 64) return send(res, 400, { error: "no picture" });
  const subject = String(url.searchParams.get("who") ?? "").slice(0, 200) || "the person in the reference photo";
  painting.add(id);
  send(res, 202, { ok: true, painting: true });
  let out = null;
  try { out = await paint(bytes, ext, `${subject}, with the face and likeness of the person in the reference photo`); } catch (e) { console.error("likeness:", e.message); }
  try { out ? keep(ctx, id, out, "png") : keep(ctx, id, bytes, ext); } catch (e) { console.error("likeness keep:", e.message); }
  painting.delete(id);
}

// GET /portraits: whose own portraits the reign has, and who is still being painted.
export function list(ctx, req, res) {
  let ids = [];
  try { ids = [...new Set(fs.readdirSync(dir(ctx)).filter((f) => /\.(png|jpg)$/.test(f)).map((f) => f.replace(/\.(png|jpg)$/, "")))]; } catch { /* none yet */ }
  send(res, 200, { ids, painting: [...painting] });
}

// GET /portrait?id=: that portrait's own bytes (png or jpg), or 404.
export function one(ctx, req, res, url) {
  const id = String(url.searchParams.get("id") ?? "");
  const f = ID.test(id) ? fileOf(ctx, id) : null;
  if (!f) return send(res, 404, { error: "no portrait" });
  res.writeHead(200, { "Content-Type": f.endsWith(".png") ? "image/png" : "image/jpeg" });
  res.end(fs.readFileSync(f));
}

// Plain JSON, kept out of names.js's word swaps (ids only).
function send(res, code, body) {
  res.writeHead(code, { "Content-Type": "application/json" });
  res.end(JSON.stringify(body));
}
