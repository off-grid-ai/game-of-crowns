#!/usr/bin/env python3
"""Build GoC export sizes from the saved masters. Requires ImageMagick."""
from pathlib import Path
import csv
import hashlib
import json
import shutil
import struct
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
FONT = "/System/Library/Fonts/Helvetica.ttc"
RECORDS = []
DARK = "#151719"

def run(*args):
    return subprocess.check_output([str(a) for a in args], text=True).strip()

def identify(path):
    result = run("magick", "identify", "-format", "%w %h %[channels]", path).split()
    return int(result[0]), int(result[1]), result[2]

def record(path, source=None, use="", operation="copy", expected=None):
    w, h, channels = identify(path)
    if expected:
        assert (w, h) == expected, (path.name, w, h, expected)
    sw, sh, _ = identify(source) if source else (w, h, channels)
    row = dict(
        path=str(path.relative_to(ROOT)), width=w, height=h,
        format=path.suffix[1:].upper(), channels=channels,
        bytes=path.stat().st_size,
        sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        source=str(source.relative_to(ROOT)) if source else "",
        source_width=sw, source_height=sh, operation=operation,
        enlarged=bool(w > sw or h > sh), use=use,
    )
    RECORDS.append(row)
    return row

def export(source, destination, w, h, use, mode="cover", alpha=False):
    source = ROOT / source
    destination = ROOT / destination
    destination.parent.mkdir(parents=True, exist_ok=True)
    args = ["magick", source, "-auto-orient", "-colorspace", "sRGB"]
    if mode == "cover":
        args += ["-resize", f"{w}x{h}^", "-gravity", "center", "-extent", f"{w}x{h}"]
    else:
        args += ["-resize", f"{w}x{h}", "-background", "none" if alpha else DARK,
                 "-gravity", "center", "-extent", f"{w}x{h}"]
    if not alpha:
        args += ["-background", DARK, "-alpha", "remove", "-alpha", "off"]
    if destination.suffix.lower() == ".jpg":
        args += ["-sampling-factor", "4:4:4", "-quality", "91"]
    else:
        args += ["-define", "png:color-type=6" if alpha else "png:color-type=2"]
    args += ["-depth", "8", "-strip", destination]
    run(*args)
    record(destination, source, use, mode, (w, h))
    return destination

def copy_image(source, destination, use):
    source, destination = ROOT / source, ROOT / destination
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    record(destination, source, use)

def make_preview(source, destination, label, width=760, height=490):
    run("magick", "-size", f"{width}x{height}", f"xc:{DARK}",
        "(", ROOT / source, "-resize", f"{width-60}x{height-100}", ")",
        "-gravity", "center", "-compose", "over", "-composite",
        "-font", FONT, "-fill", "#D9D0BF", "-pointsize", "20",
        "-gravity", "southwest", "-annotate", "+28+24", label,
        ROOT / destination)

def main():
    assert shutil.which("magick"), "ImageMagick is required."
    assert shutil.which("iconutil"), "macOS iconutil is required for ICNS."
    masters = ROOT / "masters"
    for p in sorted(masters.glob("*.png")):
        record(p, use="Original artwork source; preserve its native dimensions.")

    copy_image("masters/full-title-selected-c.png", "logos/full-title-original.png",
               "Approved option C; transparent full game title.")
    copy_image("masters/goc-monogram.png", "logos/goc-monogram-original.png",
               "Transparent GoC short mark.")
    export("masters/full-title-selected-c.png", "logos/full-title-1280.png",
           1280, 427, "Full title for digital layouts.", "contain", True)
    export("masters/full-title-selected-c.png", "logos/full-title-640.png",
           640, 214, "Smaller full title.", "contain", True)
    for size in (1024, 512, 150):
        name = "goc-video-watermark-150.png" if size == 150 else f"goc-monogram-{size}.png"
        export("masters/goc-monogram.png", f"logos/{name}", size, size,
               "Transparent GoC mark; 150 px file is for video watermark use.",
               "contain", True)
    for size in (1024, 512, 256, 192, 180, 128, 64, 48, 32, 16):
        export("masters/app-icon.png", f"icons/goc-{size}.png", size, size,
               "GoC app icon. The 16 px version is for technical use.")
    for size in (400, 512):
        export("masters/app-icon.png", f"social/avatar-{size}.png", size, size,
               "Social profile image; checked with a circular crop.")

    iconset = ROOT / "icons/goc.iconset"
    iconset.mkdir(exist_ok=True)
    for base in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            size = base * scale
            suffix = "@2x" if scale == 2 else ""
            export("masters/app-icon.png",
                   f"icons/goc.iconset/icon_{base}x{base}{suffix}.png",
                   size, size, "macOS iconset source.", alpha=True)
    run("iconutil", "-c", "icns", iconset, "-o", ROOT / "icons/goc.icns")
    run("magick", ROOT / "icons/goc-256.png", "-define",
        "icon:auto-resize=256,128,64,48,32,24,16", ROOT / "icons/goc.ico")
    ico = (ROOT / "icons/goc.ico").read_bytes()
    assert struct.unpack("<HHH", ico[:6]) == (0, 1, 7)
    icns = (ROOT / "icons/goc.icns").read_bytes()
    assert icns[:4] == b"icns" and struct.unpack(">I", icns[4:8])[0] == len(icns)
    for name, description in (
        ("goc.ico", "Windows icon; 16, 24, 32, 48, 64, 128, and 256 px frames."),
        ("goc.icns", "macOS icon; standard and Retina frames up to 1024 px."),
    ):
        p = ROOT / "icons" / name
        RECORDS.append(dict(path=f"icons/{name}", width="", height="",
                            format=p.suffix[1:].upper(), channels="multiple frames",
                            bytes=p.stat().st_size,
                            sha256=hashlib.sha256(p.read_bytes()).hexdigest(),
                            source="masters/app-icon.png", source_width=1254,
                            source_height=1254, operation="native icon encoding",
                            enlarged=False, use=description))

    specs = [
        ("channel-banner", "social/x-header-1500x500.jpg", 1500, 500, "X profile header."),
        ("channel-banner", "social/youtube-banner-2560x1440.jpg", 2560, 1440, "YouTube channel banner; title in central safe area."),
        ("key-art-landscape", "social/post-landscape-1920x1080.jpg", 1920, 1080, "Landscape promotional illustration."),
        ("key-art-landscape", "social/link-preview-1200x630.jpg", 1200, 630, "Website and social link preview artwork."),
        ("key-art-landscape", "social/youtube-thumbnail-1280x720.jpg", 1280, 720, "Promotional video thumbnail artwork."),
        ("key-art-square", "social/post-square-1080x1080.jpg", 1080, 1080, "Square promotional post."),
        ("key-art-portrait", "social/post-portrait-1080x1350.jpg", 1080, 1350, "Portrait promotional post."),
        ("key-art-portrait", "social/story-1080x1920.jpg", 1080, 1920, "Vertical story artwork; centre crop."),
        ("landscape-original", "social/discord-banner-960x540.jpg", 960, 540, "Discord server banner without title text."),
        ("compact-title-card", "social/email-header-1200x450.jpg", 1200, 450, "Dark title artwork for email or a general banner."),
        ("key-art-landscape", "store/header-capsule-920x430.png", 920, 430, "Prepared Steam header capsule; illustration and title."),
        ("compact-title-card", "store/small-capsule-462x174.png", 462, 174, "Prepared Steam small capsule; large, clear title."),
        ("key-art-landscape", "store/main-capsule-1232x706.png", 1232, 706, "Prepared Steam main capsule; illustration and title."),
        ("key-art-portrait", "store/vertical-capsule-748x896.png", 748, 896, "Prepared Steam vertical capsule."),
        ("key-art-portrait", "store/library-capsule-600x900.png", 600, 900, "Prepared Steam library capsule."),
        ("key-art-landscape", "store/library-header-920x430.png", 920, 430, "Prepared Steam library header."),
        ("landscape-original", "store/library-hero-3840x1240.png", 3840, 1240, "Prepared Steam library hero without title text; source landscape was previously enlarged."),
        ("app-icon", "store/community-icon-184x184.jpg", 184, 184, "Prepared Steam community icon."),
        ("app-icon", "store/shortcut-icon-256x256.png", 256, 256, "Prepared Steam shortcut icon."),
        ("landscape-original", "backgrounds/landscape-1920x1080.jpg", 1920, 1080, "Unbranded promotional landscape."),
    ]
    for source, destination, w, h, use in specs:
        export(f"masters/{source}.png", destination, w, h, use)
    export("masters/full-title-selected-c.png", "store/library-logo-1280.png",
           1280, 427, "Prepared Steam library title overlay.", "contain", True)
    copy_image("masters/landscape-original.png", "backgrounds/landscape-3840x2160.png",
               "Unbranded landscape; previously enlarged from 1672 x 941.")

    # Review images show the actual exports; labels and masks are for review only.
    tiles = [
        ("icons/goc-512.png", "GoC app icon"),
        ("logos/full-title-original.png", "Selected full title / transparent"),
        ("logos/goc-monogram-512.png", "GoC mark / transparent"),
        ("social/x-header-1500x500.jpg", "X header / 1500 x 500"),
        ("social/youtube-banner-2560x1440.jpg", "YouTube banner / 2560 x 1440"),
        ("social/post-landscape-1920x1080.jpg", "Landscape post / 1920 x 1080"),
        ("social/post-square-1080x1080.jpg", "Square post / 1080 x 1080"),
        ("social/post-portrait-1080x1350.jpg", "Portrait post / 1080 x 1350"),
        ("social/story-1080x1920.jpg", "Story / 1080 x 1920"),
        ("store/main-capsule-1232x706.png", "Steam main capsule"),
        ("store/vertical-capsule-748x896.png", "Steam vertical capsule"),
        ("store/small-capsule-462x174.png", "Steam small capsule"),
    ]
    tile_paths = []
    for i, (src, title) in enumerate(tiles):
        dest = f"previews/tile-{i+1:02}.png"
        make_preview(src, dest, title)
        tile_paths.append(ROOT / dest)
    overview = ROOT / "previews/asset-overview.jpg"
    run("magick", "montage", "-font", FONT, *tile_paths, "-tile", "3x4", "-geometry", "+0+0",
        "-background", DARK, "-quality", "90", overview)
    for p in tile_paths:
        p.unlink()
    record(overview, use="Review sheet; dark backgrounds are for review only.")

    banner = ROOT / "social/youtube-banner-2560x1440.jpg"
    guide = ROOT / "previews/youtube-safe-area.jpg"
    run("magick", banner, "-fill", "none", "-stroke", "#d7c6a4", "-strokewidth", "3",
        "-draw", "rectangle 508,510 2052,930", "-quality", "90", guide)
    record(guide, banner, "Review only: rectangle marks the central title safe area.",
           "review guide", (2560, 1440))

    avatar = ROOT / "previews/avatar-circle.png"
    run("magick", ROOT / "icons/goc-512.png", "-resize", "256x256",
        "(", "-size", "256x256", "xc:none", "-fill", "white", "-draw",
        "circle 128,128 128,0", ")", "-alpha", "on", "-compose", "DstIn",
        "-composite", avatar)
    record(avatar, ROOT / "icons/goc-512.png", "Circular profile crop review.")

    small = ROOT / "previews/small-capsule-120x45.png"
    run("magick", ROOT / "store/small-capsule-462x174.png", "-resize", "120x45!",
        small)
    record(small, ROOT / "store/small-capsule-462x174.png",
           "Review at the small Steam display size.", "resize", (120, 45))

    size_tiles = []
    for size in (16, 32, 48, 64, 128, 256):
        tile = ROOT / f"previews/icon-review-{size}.png"
        run("magick", "-size", "300x330", f"xc:{DARK}",
            "(", ROOT / f"icons/goc-{size}.png", ")", "-gravity", "center",
            "-compose", "over", "-composite", "-font", FONT,
            "-fill", "#D9D0BF", "-pointsize", "18", "-gravity", "south",
            "-annotate", "+0+18", f"{size} px / actual pixels", tile)
        size_tiles.append(tile)
    icon_review = ROOT / "previews/icon-size-review.png"
    run("magick", "montage", "-font", FONT, *size_tiles, "-tile", "3x2",
        "-geometry", "+0+0", "-background", DARK, icon_review)
    for p in size_tiles:
        p.unlink()
    record(icon_review, use="Review of app icon exports at their actual pixel sizes.")

    # Confirm real alpha in each overlay and enforce upload file limits.
    for f in ("logos/full-title-original.png", "logos/goc-monogram-original.png",
              "logos/goc-video-watermark-150.png", "store/library-logo-1280.png"):
        lo, hi = map(float, run("magick", ROOT / f, "-alpha", "extract",
                               "-format", "%[fx:minima] %[fx:maxima]", "info:").split())
        assert lo == 0 and hi > 0, (f, lo, hi)
    assert banner.stat().st_size <= 6_000_000
    assert (ROOT / "social/avatar-400.png").stat().st_size < 2_000_000
    assert (ROOT / "logos/goc-video-watermark-150.png").stat().st_size < 1_000_000

    RECORDS.sort(key=lambda r: r["path"])
    (ROOT / "manifest.json").write_text(json.dumps(RECORDS, indent=2) + "\n")
    with (ROOT / "manifest.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=RECORDS[0].keys())
        writer.writeheader()
        writer.writerows(RECORDS)
    summary = {
        "date": "2026-11-04", "image_and_icon_files": len(RECORDS),
        "enlarged_exports": sum(bool(r["enlarged"]) for r in RECORDS),
        "checks": ["export dimensions", "PNG/JPEG decoding", "real logo alpha",
                   "ICO frame count", "ICNS container length", "upload file limits"],
        "visual_checks_required": ["spelling", "crop safety", "small icon",
                                   "circular avatar", "YouTube safe area"],
    }
    (ROOT / "press/build-report.json").write_text(json.dumps(summary, indent=2) + "\n")
    archive = ROOT.parent / "game-of-crowns-media-kit.zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
        for p in sorted(ROOT.rglob("*")):
            if p.is_file() and p.name != ".DS_Store" and "__pycache__" not in p.parts:
                bundle.write(p, Path("game-of-crowns-media-kit") / p.relative_to(ROOT))
    with zipfile.ZipFile(archive) as bundle:
        assert bundle.testzip() is None
    print(f"Built {len(RECORDS)} image and icon files.")
    print(f"Archive: {archive} ({archive.stat().st_size / 1_000_000:.1f} MB)")
    print(f"Preview: {overview}")

if __name__ == "__main__":
    main()

