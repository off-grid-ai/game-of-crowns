"""Painted portraits for the court, from public-domain museum paintings (the supervisor's
pick: portraits-pick.md; references CK2 and King of Dragon Pass's painted faces).

One offline pipeline, run once, so hundreds of faces read as one painter's:
  sources  -> the Met's open API (CC0 data, public-domain images); more museums are added as fetchers
  filter   -> head-and-shoulders portraits, one clear face, no named king, pope or saint
  crop     -> OpenCV's YuNet face detector (opencv_zoo, Apache-2.0): every face at the same
              scale with the eyes on the same line, 3:4
  grade    -> one warm varnish grade and a soft vignette for every face
  out      -> realm/assets/portraits/painted/<museum>-<id>.jpg (384x512) and sources.json:
              museum, id, title, artist, year, licence, sex and age (from the title; checked by eye)
The frame and the house's colours go on in the game (the court card), since they depend on the lord.

Run:  python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
      .venv/bin/python build.py --model face_detection_yunet_2023mar.onnx --cache ~/Library/Caches/goc-portraits
"""
import argparse, json, os, re, time, urllib.parse, urllib.request
import cv2
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "portraits", "painted"))
UA = {"User-Agent": "game-of-crowns-portraits (offline asset build)"}
W, H = 384, 512          # the output plate
EYE_Y = 0.40             # the eyes' line, as a share of the plate's height
FACE_H = 0.34            # the face's height (brow to chin), as a share of the plate's height
# Sitters a player might recognise, or not a portrait at all: royals, the church's great, famous
# patrons, poets and reformers, prophets and gods (the supervisor's name list; a by-eye pass, drop.txt, after).
NAMED = re.compile(r"\b(king|queen|pope|emperor|empress|cardinal|saint|st\.|christ|madonna|virgin|duke|duchess|prince|princess"
                   r"|elizabeth|tudor|medici|sforza|este|gonzaga|habsburg|valois|bourbon|stuart|dante|petrarch|erasmus|luther|calvin"
                   r"|prophet|prophetess|apostle|evangelist|bacchus|apollo|venus|mars|minerva|allegory|vanitas)\b", re.I)


def get(url, binary=False):
    for i in range(3):
        try:
            data = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read()
            return data if binary else json.loads(data)
        except Exception as e:
            err = e
            time.sleep(1 + i)
    raise err


def tag(title):
    t = title.lower()
    sex = "f" if re.search(r"\b(woman|lady|girl|wife|daughter|widow|mother)\b", t) else "m" if re.search(r"\b(man|gentleman|boy|youth|knight|husband|son|merchant|bishop)\b", t) else "?"
    age = "old" if re.search(r"\b(old|elderly|aged)\b", t) else "young" if re.search(r"\b(young|boy|girl|child|youth)\b", t) else "adult"
    return sex, age


def met_sources(limit=0):
    api = "https://collectionapi.metmuseum.org/public/collection/v1.1"  # v1 search was retired on 2026-10-01
    ids = set()
    for q in ("portrait", "portrait of a woman", "portrait of a man", "portrait of a young", "portrait of an old"):
        r = get(f"{api}/search?departmentId=11&dateBegin=1400&dateEnd=1650&hasImages=true&q=" + urllib.parse.quote(q))
        ids |= set(r.get("objectIDs") or [])
    out = []
    for i in sorted(ids):
        o = None
        for ver in (api.replace("/v1.1", "/v1"), api):  # objects answer on v1 (v1.1 has search only, 2026-11)
            try:
                o = get(f"{ver}/objects/{i}")
                break
            except Exception:
                continue
        if o is None:
            continue
        title = o.get("title") or ""
        if not o.get("isPublicDomain") or not o.get("primaryImage") or "portrait" not in title.lower() or NAMED.search(title):
            continue
        out.append({"museum": "met", "id": str(i), "title": title, "artist": o.get("artistDisplayName"), "year": o.get("objectBeginDate"),
                    "licence": "CC0 (The Met Open Access)", "url": o.get("primaryImageSmall") or o["primaryImage"],
                    "page": o.get("objectURL")})
        time.sleep(0.02)
        if limit and len(out) >= limit:
            break
    return out


def nga_sources(objects_csv, images_csv, limit=0):
    """The National Gallery of Art's open data (CC0; github.com/NationalGalleryOfArt/opendata):
    paintings 1400-1650 titled as portraits, with their primary open-access image (IIIF)."""
    import csv
    csv.field_size_limit(10 ** 9)
    keep = {}
    with open(objects_csv, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            title = r.get("title") or ""
            try:
                y = int(r.get("beginyear") or 0)
            except ValueError:
                continue
            if r.get("classification") != "Painting" or not 1400 <= y <= 1650 or "portrait" not in title.lower() or NAMED.search(title):
                continue
            keep[r["objectid"]] = {"museum": "nga", "id": r["objectid"], "title": title, "artist": r.get("attribution"), "year": y,
                                   "licence": "CC0 (National Gallery of Art open access)", "page": f"https://www.nga.gov/collection/art-object-page.{r['objectid']}.html"}
    out = []
    with open(images_csv, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            o = keep.get(r.get("depictstmsobjectid"))
            if o and r.get("viewtype") == "primary" and r.get("openaccess") == "1" and "url" not in o:
                o["url"] = r["iiifurl"].rstrip("/") + "/full/!1200,1200/0/default.jpg"
                out.append(o)
                if limit and len(out) >= limit:
                    break
    return out


def rijks_sources(limit=0):
    """The Rijksmuseum's open data (public domain; data.rijksmuseum.nl, Linked Art, no key):
    paintings to 1650 titled as portraits or old people, each followed to its IIIF image."""
    LD = {**UA, "Accept": "application/ld+json"}
    ld = lambda u: json.loads(urllib.request.urlopen(urllib.request.Request(u, headers=LD), timeout=60).read())
    EN = "http://vocab.getty.edu/aat/300388277"
    ids = []
    for q in ("portrait of a woman", "portrait of a young woman", "old woman", "portrait of an old", "old man", "portrait of a man", "portrait of a girl", "portrait of a boy"):
        url = "https://data.rijksmuseum.nl/search/collection?type=painting&title=" + urllib.parse.quote(q)
        while url:
            try:
                page = get(url)
            except Exception:
                break
            ids += [x["id"] for x in page.get("orderedItems", []) if x["id"] not in ids]
            url = (page.get("next") or {}).get("id")
    out = []
    for i in ids:
        try:
            item = ld(i)
            title = next((n["content"] for n in item.get("identified_by", []) if n.get("type") == "Name" and any(l.get("id") == EN for l in n.get("language", []))), "")
            ts = (item.get("produced_by") or {}).get("timespan") or {}
            year = int(str(ts.get("begin_of_the_begin", "9999"))[:4])
            t = title.lower()
            if year > 1650 or not title or NAMED.search(title) or not ("portrait" in t or "old woman" in t or "old man" in t):
                continue
            vi = ld(item["shows"][0]["id"])
            do = ld(vi["digitally_shown_by"][0]["id"])
            img = do["access_point"][0]["id"].replace("/full/max/", "/full/1200,/")
        except Exception:
            continue
        num = next((n["content"] for n in item.get("identified_by", []) if n.get("type") == "Identifier"), i.rsplit("/", 1)[-1])
        out.append({"museum": "rijks", "id": i.rsplit("/", 1)[-1], "title": title, "artist": None, "year": year, "licence": "Public domain (Rijksmuseum open data)",
                    "url": img, "page": f"https://www.rijksmuseum.nl/en/collection/{num}"})
        if limit and len(out) >= limit:
            break
    return out


def detector(model):
    return cv2.FaceDetectorYN.create(model, "", (320, 320), 0.8, 0.3, 5000)


def crop(img, det):
    h, w = img.shape[:2]
    det.setInputSize((w, h))
    _, faces = det.detect(img)
    if faces is None or len(faces) == 0:
        return None, "no face"
    faces = sorted(faces, key=lambda f: -f[2] * f[3])
    if len(faces) > 1 and faces[1][2] * faces[1][3] > 0.35 * faces[0][2] * faces[0][3]:
        return None, "two faces"
    x, y, fw, fh = faces[0][:4]
    eyes_y = (faces[0][5] + faces[0][7]) / 2.0          # right and left eye y
    cx = x + fw / 2.0
    scale = (FACE_H * H) / fh                            # the face to its share of the plate
    cw, ch = W / scale, H / scale                        # the crop in source pixels
    x0, y0 = cx - cw / 2.0, eyes_y - EYE_Y * ch
    if x0 < -0.08 * cw or y0 < -0.08 * ch or x0 + cw > w + 0.08 * cw or y0 + ch > h + 0.08 * ch:
        return None, "face too near the edge"
    m = np.float32([[scale, 0, -x0 * scale], [0, scale, -y0 * scale]])
    return cv2.warpAffine(img, m, (W, H), flags=cv2.INTER_AREA, borderMode=cv2.BORDER_REPLICATE), "ok"


def grade(img):
    f = img.astype(np.float32) / 255.0
    grey = f.mean(axis=2, keepdims=True)
    f = grey + (f - grey) * 0.85                          # a little less saturated
    f = f * np.array([0.90, 0.99, 1.05], np.float32)      # warm varnish (BGR)
    f = np.clip((f - 0.03) * 1.06, 0, 1)                  # a touch more depth in the darks
    yy, xx = np.mgrid[0:H, 0:W]
    r = np.sqrt(((xx - W / 2) / (W / 2)) ** 2 + ((yy - H * 0.45) / (H / 2)) ** 2)
    f *= (1 - 0.35 * np.clip(r - 0.55, 0, 1))[..., None]  # a soft vignette
    return (np.clip(f, 0, 1) * 255).astype(np.uint8)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--cache", required=True)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--nga-objects", help="NGA open data objects.csv (adds the National Gallery of Art)")
    ap.add_argument("--nga-images", help="NGA open data published_images.csv")
    ap.add_argument("--only", choices=["met", "nga", "rijks"], help="one museum only")
    ap.add_argument("--rijks", action="store_true", help="add the Rijksmuseum (slow: three requests a work)")
    a = ap.parse_args()
    os.makedirs(a.cache, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    det = detector(a.model)
    sources = met_sources(a.limit) if a.only in (None, "met") else []
    if a.nga_objects and a.nga_images and a.only in (None, "nga"):
        sources += nga_sources(a.nga_objects, a.nga_images, a.limit)
    if (a.rijks and a.only is None) or a.only == "rijks":
        sources += rijks_sources(a.limit)
    kept, why = [], {}
    # Dropped by eye (drop.txt): recognisable sitters, prints, frames and medallions.
    drop = {l.split("#")[0].strip() for l in open(os.path.join(HERE, "drop.txt")) if l.strip() and not l.startswith("#")} if os.path.exists(os.path.join(HERE, "drop.txt")) else set()
    sources = [s for s in sources if f"{s['museum']}-{s['id']}.jpg" not in drop]
    for s in sources:
        path = os.path.join(a.cache, f"{s['museum']}-{s['id']}.jpg")
        if not os.path.exists(path):
            try:
                open(path, "wb").write(get(s["url"], binary=True))
            except Exception:
                why["download failed"] = why.get("download failed", 0) + 1
                continue
        img = cv2.imread(path)
        if img is None:
            continue
        face, reason = crop(img, det)
        if face is None:
            why[reason] = why.get(reason, 0) + 1
            continue
        name = f"{s['museum']}-{s['id']}.jpg"
        cv2.imwrite(os.path.join(OUT, name), grade(face), [cv2.IMWRITE_JPEG_QUALITY, 88])
        sex, age = tag(s["title"])
        kept.append({k: v for k, v in s.items() if k != "url"} | {"file": name, "sex": sex, "age": age})
    json.dump({"_": "Painted portraits (realm/tools/portraits/build.py): public-domain museum paintings, cropped and graded as one. sex and age come from the title; '?' is checked by eye.",
               "portraits": kept}, open(os.path.join(OUT, "sources.json"), "w"), indent=1)
    print(json.dumps({"sources": len(sources), "kept": len(kept), "dropped": why,
                      "women": sum(k["sex"] == "f" for k in kept), "men": sum(k["sex"] == "m" for k in kept), "unsexed": sum(k["sex"] == "?" for k in kept),
                      "old": sum(k["age"] == "old" for k in kept), "young": sum(k["age"] == "young" for k in kept)}, indent=1))


if __name__ == "__main__":
    main()
