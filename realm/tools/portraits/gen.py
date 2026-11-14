"""Generated painted faces for the court: Mac's go, 2026-11-14 (the museum set keeps only the 20 faces painted before
1500, realm/data/faces.json). Each face is made by the Codex CLI's image tool from one fixed style (style.md) and a
plain subject (court_subjects.json: kind, sex, age, child, subject), then goes through build.py's own crop and grade,
so it reads as the same painter's as the museum faces. Each is added to sources.json (marked "generated", with its
prompt) and to faces.json's kept list with its kind.

Run:  python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
      .venv/bin/python gen.py --model face_detection_yunet_2023mar.onnx --cache ~/Library/Caches/goc-portraits --jobs 4
Images already made (same prompt) are only cropped again; the Codex runs go in parallel (each finds its image by its
own session id), the crop, grade and the two lists after, in one pass.
"""
import argparse, concurrent.futures, glob, hashlib, json, os, re, shutil, subprocess
import sys
import cv2
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # build.py, beside this file
import build

CODEX = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
IMAGES = os.path.expanduser("~/.codex/generated_images")
FACES = os.path.normpath(os.path.join(build.HERE, "..", "..", "data", "faces.json"))


def style():
    text = open(os.path.join(build.HERE, "style.md")).read()
    return re.search(r"```\n(.*?)\n```", text, re.S).group(1).replace("\n", " ")


def generate(prompt, work):
    run = subprocess.run([CODEX, "exec", "--skip-git-repo-check", "-C", work,
                          "Make exactly one image with your image generation tool, from this prompt, and nothing else "
                          "(no files, no code, no edits): " + prompt], timeout=900,
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    sid = re.search(r"session id: (\S+)", run.stderr or "")
    made = glob.glob(os.path.join(IMAGES, sid.group(1), "*.png")) if sid else []
    return max(made, key=os.path.getmtime) if made else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--cache", required=True)
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--subjects", default=os.path.join(build.HERE, "court_subjects.json"))
    a = ap.parse_args()
    os.makedirs(a.cache, exist_ok=True)
    todo = []
    for s in json.load(open(a.subjects))["faces"]:
        prompt = style().format(subject=s["subject"])
        gid = hashlib.sha1(prompt.encode()).hexdigest()[:10]
        todo.append((s, prompt, gid, os.path.join(a.cache, f"generated-{gid}.png")))

    def make(t):
        s, prompt, gid, raw = t
        if not os.path.exists(raw):
            got = generate(prompt, a.cache)
            if got is None:
                return gid, "codex made no image"
            shutil.copy(got, raw)
        return gid, "ok"
    with concurrent.futures.ThreadPoolExecutor(a.jobs) as ex:
        for gid, why in ex.map(make, todo):
            if why != "ok":
                print(f"generated-{gid}: {why}")

    det = build.detector(a.model)
    path = os.path.join(build.OUT, "sources.json")
    d = json.load(open(path))
    faces = json.load(open(FACES))
    for s, prompt, gid, raw in todo:
        if not os.path.exists(raw):
            continue
        face, reason = build.crop(cv2.imread(raw), det)
        if face is None:
            print(f"generated-{gid}: {reason} (raw at {raw})")
            continue
        name = f"generated-{gid}.jpg"
        cv2.imwrite(os.path.join(build.OUT, name), build.grade(face), [cv2.IMWRITE_JPEG_QUALITY, 88])
        d["portraits"] = [p for p in d["portraits"] if p["file"] != name] + [
            {"museum": "generated", "id": gid, "title": s["subject"], "artist": "generated (Codex image tool)",
             "year": None, "licence": "generated", "prompt": prompt, "file": name, "sex": s["sex"], "age": s["age"],
             "child": bool(s["child"]), "kind": s["kind"]}]
        if name not in faces["kept"]:
            faces["kept"].append(name)
        faces.setdefault("kinds", {})[name] = s["kind"]
        print(name, s["kind"])
    json.dump(d, open(path, "w"), indent=1)
    json.dump(faces, open(FACES, "w"), indent=1)


if __name__ == "__main__":
    main()
