# Meshy through its API, headless (Mac 2026-11-12: no browser, no manual steps). The key is read from the macOS
# keychain at run time (`security find-generic-password -a goc -s meshy-api-key -w`) and never printed or written.
#   python3 -I realm/tools/meshy_api.py model <concept.png> <out.glb> [json overrides]   image-to-3D, then the GLB
#   python3 -I realm/tools/meshy_api.py rig <image-to-3d task id> <out.glb> [height m]   a person's Mixamo rig
#   python3 -I realm/tools/meshy_api.py fetch <image-to-3d task id> <out.glb>             wait for a task already made
#   python3 -I realm/tools/meshy_api.py retexture <image-to-3d task id> <style.png> <out.glb> [json overrides]
#       paint a model (a mesh-only preview: model with {"should_texture": false}) from one style image, keeping its
#       UVs (docs/art/STANDARDS.md §6 steps 3-4: preview the shape, judge it, then spend on the paint)
#   python3 -I realm/tools/meshy_api.py balance
# model: the square set's settings (docs/research/meshy-square-set.md) as the API names them: latest (Meshy 7.1),
# 2k geometry, Meshy 7 texture at 2k with PBR, image enhancement, remeshed in triangles (target_polycount, 10k unless
# overridden; "pose_mode": "a-pose" for a person). Single image: the API's multi-view takes views we'd have to draw.
# Prints TASK <id>, STATUS <status> credits <n>, WROTE <path>. Credits go in docs/research (meshy-beasts.md).
import base64, json, subprocess, sys, time, urllib.error, urllib.request

API = "https://api.meshy.ai/openapi/v1/"


def _key():
    return subprocess.run(["security", "find-generic-password", "-a", "goc", "-s", "meshy-api-key", "-w"],
                          capture_output=True, text=True).stdout.strip()


def _call(method, path, body=None):
    h = {"Authorization": "Bearer " + _key(), "Content-Type": "application/json"}
    for tries in range(6):  # a dropped connection on a read is tried again; a create is never sent twice
        r = urllib.request.Request(API + path, data=json.dumps(body).encode() if body else None, headers=h, method=method)
        try:
            return json.load(urllib.request.urlopen(r, timeout=120))
        except urllib.error.HTTPError as e:
            raise RuntimeError("Meshy %s %s: %s" % (e.code, path, e.read().decode()[:400]))
        except (urllib.error.URLError, TimeoutError):
            if method != "GET":
                raise
            time.sleep(10 * (tries + 1))
    raise RuntimeError("Meshy unreachable: " + path)


def _wait(kind, tid, every):
    while True:
        t = _call("GET", kind + "/" + tid)
        if t["status"] in ("SUCCEEDED", "FAILED", "CANCELED", "EXPIRED"):
            print("STATUS", t["status"], "credits", t.get("consumed_credits"), (t.get("task_error") or {}).get("message", ""), flush=True)
            return t
        time.sleep(every)


def fetch(tid, out):
    t = _wait("image-to-3d", tid, 15)
    if t["status"] == "SUCCEEDED":
        urllib.request.urlretrieve(t["model_urls"]["glb"], out)
        print("WROTE", out)


def model(img, out, extra):
    body = {"image_url": "data:image/png;base64," + base64.b64encode(open(img, "rb").read()).decode(),
            "ai_model": "latest", "geometry_resolution": "2k", "should_texture": True, "texture_model": "meshy-7",
            "texture_resolution": "2k", "enable_pbr": True, "image_enhancement": True, "should_remesh": True,
            "topology": "triangle", "target_polycount": 10000, "target_formats": ["glb"]}
    body.update(extra)
    if not body.get("should_texture", True):  # a shape preview: no paint settings (the API refuses them)
        for k in ("texture_model", "texture_resolution", "enable_pbr", "texture_prompt", "texture_image_url"):
            body.pop(k, None)
    tid = _call("POST", "image-to-3d", body)["result"]
    print("TASK", tid, flush=True)
    t = _wait("image-to-3d", tid, 15)
    if t["status"] == "SUCCEEDED":
        urllib.request.urlretrieve(t["model_urls"]["glb"], out)
        print("WROTE", out)


def retexture(task_id, img, out, extra):
    body = {"input_task_id": task_id, "image_style_url": "data:image/png;base64," + base64.b64encode(open(img, "rb").read()).decode(),
            "ai_model": "latest", "enable_original_uv": True, "enable_pbr": False}
    body.update(extra)
    tid = _call("POST", "retexture", body)["result"]
    print("TASK", tid, flush=True)
    t = _wait("retexture", tid, 15)
    if t["status"] == "SUCCEEDED":
        urllib.request.urlretrieve(t["model_urls"]["glb"], out)
        print("WROTE", out)


def rig(task_id, out, height):
    tid = _call("POST", "rigging", {"input_task_id": task_id, "height_meters": height, "skeleton_template": "mixamo"})["result"]
    print("TASK", tid, flush=True)
    t = _wait("rigging", tid, 10)
    if t["status"] == "SUCCEEDED":
        urllib.request.urlretrieve(t["result"]["rigged_character_glb_url"], out)
        print("WROTE", out)


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[0] == "model":
        model(a[1], a[2], json.loads(a[3]) if len(a) > 3 else {})
    elif a[0] == "retexture":
        retexture(a[1], a[2], a[3], json.loads(a[4]) if len(a) > 4 else {})
    elif a[0] == "rig":
        rig(a[1], a[2], float(a[3]) if len(a) > 3 else 1.75)
    elif a[0] == "fetch":
        fetch(a[1], a[2])
    elif a[0] == "balance":
        print(_call("GET", "balance"))
