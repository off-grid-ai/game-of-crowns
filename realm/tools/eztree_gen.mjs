// Usage: in a scratch folder, npm install @dgreenheck/ez-tree@1.1.0 three@0.169.0, then
//   node realm/tools/eztree_gen.mjs "Oak Medium" 7 realm/assets/nature/eztree/oak_medium.glb   (the tree bake-off's candidate b)
// EZ-Tree (dgreenheck, MIT) in Node: one preset tree generated and written as GLB (geometry and UVs; textures are
// ours, set in Godot). Browser bits it touches are stubbed: image loading (never completes) and FileReader.
import fs from "node:fs";
globalThis.self = globalThis;
globalThis.window = globalThis;
const fakeEl = () => ({ addEventListener() {}, removeEventListener() {}, style: {}, setAttribute() {}, getContext() { return null; } });
globalThis.document = { createElementNS: fakeEl, createElement: fakeEl };
globalThis.FileReader = class {
	readAsArrayBuffer(blob) { blob.arrayBuffer().then((b) => { this.result = b; this.onloadend && this.onloadend(); this.onload && this.onload({ target: this }); }); }
	readAsDataURL(blob) { blob.arrayBuffer().then((b) => { this.result = "data:application/octet-stream;base64," + Buffer.from(b).toString("base64"); this.onloadend && this.onloadend(); this.onload && this.onload({ target: this }); }); }
};
const THREE = await import("three");
const { Tree } = await import("@dgreenheck/ez-tree");
const { GLTFExporter } = await import("three/examples/jsm/exporters/GLTFExporter.js");
const preset = process.argv[2] || "Oak Medium";
const seed = Number(process.argv[3] || 7);
const out = process.argv[4] || "tree.glb";
const tree = new Tree();
tree.loadPreset(preset);
tree.options.seed = seed;
tree.generate();
// Plain named materials: the exporter would otherwise try to read the (never loaded) textures.
let n = 0;
tree.traverse((o) => {
	if (o.isMesh) {
		const leaves = /leaf|leaves/i.test(o.name) || o === tree.leavesMesh;
		o.material = new THREE.MeshStandardMaterial({ name: leaves ? "Leaves" : "Bark", side: leaves ? THREE.DoubleSide : THREE.FrontSide });
		n++;
	}
});
const box = new THREE.Box3().setFromObject(tree);
console.log("meshes", n, "size", box.getSize(new THREE.Vector3()).toArray().map((v) => v.toFixed(2)).join(" "));
new GLTFExporter().parse(tree, (glb) => { fs.writeFileSync(out, Buffer.from(glb)); console.log("wrote", out, glb.byteLength); }, (e) => { console.error("export failed", e); process.exit(1); }, { binary: true });
