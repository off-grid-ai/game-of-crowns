"""Generated painted faces, for the gaps the museums leave (the old, children): the supervisor's
call, 2026-11-11. Each face is made by the Codex CLI's image tool from one fixed style (style.md)
and a plain subject, then goes through build.py's own crop and grade, so it reads as the same
painter's. Each is marked "generated" in sources.json with its prompt (Steam's AI-content
disclosure: docs/SHIPPING.md).

Run:  .venv/bin/python gen.py --model face_detection_yunet_2023mar.onnx --cache ~/Library/Caches/goc-portraits \
          --sex f --age old "an old woman of about seventy, deep lines around the eyes, white linen cap"
Each run adds one face; one already made (same subject) is only cropped again.
"""
import argparse, glob, hashlib, json, os, re, shutil, subprocess, time
import sys
import cv2
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # build.py, beside this file
import build

CODEX = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
IMAGES = os.path.expanduser("~/.codex/generated_images")


def style():
    text = open(os.path.join(build.HERE, "style.md")).read()
    return re.search(r"```\n(.*?)\n```", text, re.S).group(1).replace("\n", " ")


def generate(prompt, work):
    before = time.time()
    subprocess.run([CODEX, "exec", "--skip-git-repo-check", "-C", work,
                    "Make exactly one image with your image generation tool, from this prompt, and nothing else "
                    "(no files, no code, no edits): " + prompt], check=True, timeout=900,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    made = [p for p in glob.glob(os.path.join(IMAGES, "*", "*.png")) if os.path.getmtime(p) >= before]
    if not made:
        raise SystemExit("codex made no image")
    return max(made, key=os.path.getmtime)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--cache", required=True)
    ap.add_argument("--sex", choices=["m", "f"], required=True)
    ap.add_argument("--age", choices=["young", "adult", "old"], required=True)
    ap.add_argument("subject")
    a = ap.parse_args()
    prompt = style().format(subject=a.subject)
    gid = hashlib.sha1(prompt.encode()).hexdigest()[:10]
    raw = os.path.join(a.cache, f"generated-{gid}.png")
    if not os.path.exists(raw):
        os.makedirs(a.cache, exist_ok=True)
        shutil.copy(generate(prompt, a.cache), raw)
    face, reason = build.crop(cv2.imread(raw), build.detector(a.model))
    if face is None:
        raise SystemExit(f"generated-{gid}: {reason} (raw at {raw})")
    name = f"generated-{gid}.jpg"
    cv2.imwrite(os.path.join(build.OUT, name), build.grade(face), [cv2.IMWRITE_JPEG_QUALITY, 88])
    path = os.path.join(build.OUT, "sources.json")
    d = json.load(open(path))
    d["portraits"] = [p for p in d["portraits"] if p["file"] != name] + [
        {"museum": "generated", "id": gid, "title": a.subject, "artist": "generated (Codex image tool)", "year": None,
         "licence": "generated: AI content, disclosed", "prompt": prompt, "file": name, "sex": a.sex, "age": a.age, "child": False}]
    json.dump(d, open(path, "w"), indent=1)
    print(name)


if __name__ == "__main__":
    main()
