"""Package the supplied Atomic Notes vector companion for the supported Android app.

No image generator, background removal, network, Flutter bootstrap or new runtime
dependency is involved. Pillow is only used for deterministic raster packaging.
Run from any directory: python tool/generate_android_branding.py [--import-source ASSETS].
The optional source is the existing user-supplied assets directory, never a download.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw
from PIL.PngImagePlugin import PngInfo

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
LIB = ASSETS / "new-atomic-icons"
RES = ROOT / "android/app/src/main/res"
ANDROID = "http://schemas.android.com/apk/res/android"
SVG = "http://www.w3.org/2000/svg"
PAPER, INK, SIGNAL = "#F4F5F1", "#15171B", "#3A2FF0"
VARIANTS = ("on-light", "on-dark", "mono-ink", "mono-white")
LAUNCHER_STROKE = 24  # Launcher-only weight; supplied companion/splash remain 11.
LAUNCHER_ARTWORK_SCALE = 2 / 3  # Relative to the previous white/purple launcher.
LAUNCHER_ADAPTIVE_RADIUS = 33 * LAUNCHER_ARTWORK_SCALE
LAUNCHER_RASTER_RADIUS_RATIO = .28  # Previous .42 radius, scaled by 2/3.
LAUNCHER_WHITE, LAUNCHER_PURPLE = "#FFFFFF", "#4B238C"
SOURCE_HASHES = {
    "atomic-icon.jpg": "3114c97ad9fe8ce43d5760e9399be135c0a0a1608b528e3aab6f4155bfa546e9",
    "Atomic Icons/devbehindyou-worker.gif": "e5993ff1ada52aa281a720d0307d53a7cffccc48839cfccca142041b8783c96a",
    "Atomic Icons/dotgrid-blink-transparent.gif": "208a81c983c0060f4a16252e9fabf97353c272269f639c2c0134cdac6f119377",
}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def import_sources(source: Path) -> dict:
    provenance = {}
    for name, expected in SOURCE_HASHES.items():
        origin = source / name
        if sha(origin) != expected:
            raise ValueError("Named source hash differs: " + name)
        target = ASSETS / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(origin, target)
        provenance[name] = {"sha256": expected, "operation": "unchanged copy"}
    ET.register_namespace("", SVG)
    for variant in VARIANTS:
        name = f"atomic-icon-{variant}"
        original = source / "new-atomic-icons/svg" / (name + ".svg")
        node = ET.parse(original).getroot()
        # C2PA metadata belongs to the supplied original, not generated derivatives.
        # Retain the original source hash; serialize only audited visual primitives.
        clean = ET.Element("{" + SVG + "}svg", {
            "viewBox": "-384 -384 768 768", "width": "1024", "height": "1024",
        })
        for child in node:
            if child.tag.rsplit("}", 1)[-1] == "g":
                clean.append(child)
        validate_vector(clean, variant)
        write(LIB / "svg" / (name + ".svg"), ET.tostring(clean, encoding="unicode") + "\n")
        origin_png = source / "new-atomic-icons/png" / (name + ".png")
        destination = LIB / "png" / (name + ".png")
        destination.parent.mkdir(parents=True, exist_ok=True)
        # Companion PNGs are supplied author artwork; keep them unchanged.
        shutil.copyfile(origin_png, destination)
        provenance["new-atomic-icons/svg/" + name + ".svg"] = {
            "sha256": sha(original), "operation": "visual primitives retained; metadata omitted",
        }
        provenance["new-atomic-icons/png/" + name + ".png"] = {
            "sha256": sha(origin_png), "operation": "unchanged copy",
        }
    for suffix in ("on-light", "on-dark"):
        name = "atomic-spin-" + suffix + ".gif"
        original = source / "new-atomic-icons/gif" / name
        destination = LIB / "gif" / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(original, destination)
        provenance["new-atomic-icons/gif/" + name] = {
            "sha256": sha(original), "operation": "unchanged supplied copy; bundled Flutter splash; not native splash",
        }
    return provenance


def palette(variant: str) -> tuple[list[str], list[str], str, str | None]:
    if variant == "launcher-white-purple":
        return [LAUNCHER_PURPLE]*3, [LAUNCHER_PURPLE]*3, LAUNCHER_PURPLE, LAUNCHER_WHITE
    if variant == "on-light":
        return [SIGNAL, SIGNAL, INK], [SIGNAL, INK, SIGNAL], INK, PAPER
    if variant == "on-dark":
        return [SIGNAL, SIGNAL, PAPER], [SIGNAL, PAPER, SIGNAL], PAPER, INK
    color = INK if variant == "mono-ink" else PAPER if variant == "mono-white" else "#FFFFFF"
    return [color] * 3, [color] * 3, color, None


def validate_vector(root: ET.Element, variant: str) -> None:
    """Refuse a silently changed reconstruction rather than approximate new artwork."""
    groups = [node for node in root if node.tag.rsplit("}", 1)[-1] == "g"]
    if len(groups) != 1 or groups[0].get("transform") != "translate(0.0 0.0) rotate(0.0) scale(1.0)":
        raise ValueError("Unsupported vector transform: " + variant)
    outer_nodes = list(groups[0])
    if not outer_nodes or outer_nodes[0].tag.rsplit("}",1)[-1] != "g" or outer_nodes[0].attrib != {"fill":"none", "stroke-width":"11"}:
        raise ValueError("Unsupported orbit style: " + variant)
    nodes = list(outer_nodes[0]) + outer_nodes[1:]
    expected_tags = ["ellipse"] * 3 + ["circle"] * 3
    if [node.tag.rsplit("}", 1)[-1] for node in nodes[:6]] != expected_tags:
        raise ValueError("Unsupported visual primitives: " + variant)
    lines, dots, outer, inner = palette(variant)
    for node, rotation, color in zip(nodes[:3], (30, -30, 90), lines):
        expected = {"rx": "336", "ry": "124", "stroke": color, "transform": f"rotate({rotation})"}
        if set(node.attrib) != set(expected) or any(node.get(key, "").lower() != value.lower() for key, value in expected.items()):
            raise ValueError("Supplied ellipse geometry changed: " + variant)
    for node, position, color in zip(nodes[3:6], (("-290.98", "-168.00"), ("290.98", "-168.00"), ("0", "336")), dots):
        expected = {"cx": position[0], "cy": position[1], "r": "26", "fill": color}
        if set(node.attrib) != set(expected) or any(node.get(key, "").lower() != value.lower() for key, value in expected.items()):
            raise ValueError("Supplied electron geometry changed: " + variant)
    if inner is not None:
        if len(nodes) != 8:
            raise ValueError("Unsupported nucleus primitives: " + variant)
        for node, radius, color in zip(nodes[6:], ("68", "25"), (outer, inner)):
            if node.tag.rsplit("}", 1)[-1] != "circle" or set(node.attrib) != {"r","fill"} or node.get("r") != radius or node.get("fill", "").lower() != color.lower():
                raise ValueError("Supplied nucleus changed: " + variant)
    else:
        expected={"fill":outer,"fill-rule":"evenodd","d":"M-68 0a68 68 0 1 0 136 0a68 68 0 1 0 -136 0zM-25 0a25 25 0 1 1 50 0a25 25 0 1 1 -50 0z"}
        if len(nodes)!=7 or nodes[6].tag.rsplit("}",1)[-1]!="path" or nodes[6].attrib!=expected:
            raise ValueError("Unsupported monochrome nucleus: " + variant)


def vector(variant: str, canvas: int, radius: float, dp: int, stroke: int = 11) -> str:
    lines, dots, outer, inner = palette(variant)
    scale = radius / 362
    ellipse = "M-336,0A336,124 0,1 0,336,0A336,124 0,1 0,-336,0Z"
    circles = lambda x, y, r: f"M{x-r},{y}a{r},{r} 0,1 0,{2*r},0a{r},{r} 0,1 0,{-2*r},0Z"
    body = []
    for rotation, color in zip((30, -30, 90), lines):
        body.append(f'        <group android:rotation="{rotation}"><path android:pathData="{ellipse}" android:fillColor="#00000000" android:strokeColor="{color}" android:strokeWidth="{stroke}"/></group>')
    for (x, y), color in zip(((-290.98, -168), (290.98, -168), (0, 336)), dots):
        body.append(f'        <path android:pathData="{circles(x, y, 26)}" android:fillColor="{color}"/>')
    nucleus = circles(0, 0, 68)
    if inner is None:
        body.append(f'        <path android:pathData="{nucleus}{circles(0, 0, 25)}" android:fillType="evenOdd" android:fillColor="{outer}"/>')
    else:
        body.append(f'        <path android:pathData="{nucleus}" android:fillColor="{outer}"/>')
        body.append(f'        <path android:pathData="{circles(0, 0, 25)}" android:fillColor="{inner}"/>')
    return (f'<?xml version="1.0" encoding="utf-8"?>\n<vector xmlns:android="{ANDROID}" android:width="{dp}dp" android:height="{dp}dp" android:viewportWidth="{canvas}" android:viewportHeight="{canvas}">\n'
            f'    <group android:translateX="{canvas/2:g}" android:translateY="{canvas/2:g}" android:scaleX="{scale:.9f}" android:scaleY="{scale:.9f}">\n'
            + "\n".join(body) + '\n    </group>\n</vector>\n')


def rgba(color: str) -> tuple[int, int, int, int]:
    return tuple(int(color[i:i+2], 16) for i in (1, 3, 5)) + (255,)


def raster(variant: str, size: int, radius: float, background: str | None = None, stroke: int = 11) -> Image.Image:
    """Supersample the audited SVG's exact ellipses/circles; no source-photo editing."""
    aa = 4
    output = Image.new("RGBA", (size * aa, size * aa), rgba(background) if background else (0, 0, 0, 0))
    draw = ImageDraw.Draw(output)
    scale, center = radius / 362 * aa, size * aa / 2
    lines, dots, outer, inner = palette(variant)
    for rotation, color in zip((30, -30, 90), lines):
        radians = math.radians(rotation)
        points = []
        edges = ([], [])
        for index in range(1441):
            theta = index * math.tau / 1440
            x, y = 336 * math.cos(theta), 124 * math.sin(theta)
            points.append((center + scale * (x * math.cos(radians) - y * math.sin(radians)),
                           center + scale * (x * math.sin(radians) + y * math.cos(radians))))
            if stroke != 11:
                # Continuous offset band avoids Pillow's short-segment joint
                # pinholes at the heavier launcher weight. The offset follows
                # the ellipse normal, preserving a uniform SVG-style stroke.
                nx, ny = math.cos(theta) / 336, math.sin(theta) / 124
                length = math.hypot(nx, ny)
                for edge, sign in zip(edges, (1, -1)):
                    ex, ey = x + sign * stroke / 2 * nx / length, y + sign * stroke / 2 * ny / length
                    edge.append((center + scale * (ex * math.cos(radians) - ey * math.sin(radians)),
                                 center + scale * (ex * math.sin(radians) + ey * math.cos(radians))))
        if stroke == 11:
            draw.line(points, fill=rgba(color), width=max(1, round(stroke * scale)), joint="curve")
        else:
            draw.polygon(edges[0] + edges[1][::-1], fill=rgba(color))
    for (x, y), color in zip(((-290.98, -168), (290.98, -168), (0, 336)), dots):
        draw.ellipse((center + (x-26)*scale, center + (y-26)*scale, center + (x+26)*scale, center + (y+26)*scale), fill=rgba(color))
    draw.ellipse((center-68*scale, center-68*scale, center+68*scale, center+68*scale), fill=rgba(outer))
    draw.ellipse((center-25*scale, center-25*scale, center+25*scale, center+25*scale), fill=rgba(inner) if inner else (0, 0, 0, 0))
    return output.resize((size, size), Image.Resampling.LANCZOS)


def save_png(path: Path, image: Image.Image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    info=PngInfo()
    info.add(b"sRGB",b"\x00")
    image.save(path, format="PNG", optimize=True, compress_level=9, pnginfo=info)


def library_and_native(relative: str, content: str) -> None:
    write(LIB / "android/native" / relative, content)
    write(RES / relative, content)


def build() -> None:
    for variant in VARIANTS:
        validate_vector(ET.parse(LIB / "svg" / f"atomic-icon-{variant}.svg").getroot(), variant)
    for name, expected in SOURCE_HASHES.items():
        if sha(ASSETS / name) != expected:
            raise ValueError("Named source hash differs: " + name)
    # 108 dp canvas, radius 22 dp: artwork is two-thirds of its former size.
    # The Android safe circle stays 66 dp; only the complete artwork scales.
    # Monochrome is deliberately its own even-odd single-color vector.
    library_and_native("drawable/atomic_launcher_foreground.xml", vector("launcher-white-purple", 108, LAUNCHER_ADAPTIVE_RADIUS, 108, LAUNCHER_STROKE))
    library_and_native("drawable/atomic_launcher_monochrome.xml", vector("themed-white", 108, LAUNCHER_ADAPTIVE_RADIUS, 108, LAUNCHER_STROKE))
    foreground = raster("launcher-white-purple", 432, LAUNCHER_ADAPTIVE_RADIUS*4, stroke=LAUNCHER_STROKE)
    monochrome = raster("themed-white", 432, LAUNCHER_ADAPTIVE_RADIUS*4, stroke=LAUNCHER_STROKE)
    save_png(LIB / "android/adaptive-foreground.png", foreground)
    save_png(LIB / "android/adaptive-monochrome.png", monochrome)
    write(LIB / "android/adaptive-background.svg", f'<svg xmlns="{SVG}" width="108" height="108" viewBox="0 0 108 108"><path fill="{LAUNCHER_WHITE}" d="M0 0h108v108H0z"/></svg>\n')
    library_and_native("values/ic_launcher_background.xml", '<?xml version="1.0" encoding="utf-8"?>\n<resources><color name="ic_launcher_background">'+LAUNCHER_WHITE+'</color></resources>\n')
    adaptive = (f'<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="{ANDROID}">\n'
                '    <background android:drawable="@color/ic_launcher_background"/>\n'
                '    <foreground android:drawable="@drawable/atomic_launcher_foreground"/>\n'
                '    <monochrome android:drawable="@drawable/atomic_launcher_monochrome"/>\n</adaptive-icon>\n')
    for name in ("launcher_icon", "ic_launcher"):
        library_and_native("mipmap-anydpi-v26/" + name + ".xml", adaptive)
    for density, size in (("mdpi",48),("hdpi",72),("xhdpi",96),("xxhdpi",144),("xxxhdpi",192)):
        image = raster("launcher-white-purple", size, size * LAUNCHER_RASTER_RADIUS_RATIO, LAUNCHER_WHITE, LAUNCHER_STROKE)
        save_png(LIB / "android/legacy" / f"launcher-{size}.png", image)
        for name in ("launcher_icon", "ic_launcher"):
            save_png(RES / ("mipmap-" + density) / (name + ".png"), image)
    # Store icon is opaque RGBA (32-bit), square, no hand-drawn outer rounding.
    save_png(LIB / "android/google-play-512.png", raster("launcher-white-purple", 512, 512*LAUNCHER_RASTER_RADIUS_RATIO, LAUNCHER_WHITE, LAUNCHER_STROKE))
    save_png(LIB / "android/launcher-source-1024.png", raster("launcher-white-purple", 1024, 1024*LAUNCHER_RASTER_RADIUS_RATIO, LAUNCHER_WHITE, LAUNCHER_STROKE))
    for variant in ("on-light", "on-dark"):
        save_png(LIB / "splash" / f"atomic-splash-{variant}.png", raster(variant, 576, 176))
    # Native Android 12+: static vector, 288 dp canvas; 176 dp artwork fits its
    # central 192 dp circle. No animation-duration or keep-on-screen callback.
    library_and_native("drawable/atomic_splash_logo.xml", vector("on-light", 288, 88, 288))
    library_and_native("drawable-night/atomic_splash_logo.xml", vector("on-dark", 288, 88, 288))
    for qualifier, color in (("values", PAPER), ("values-night", INK)):
        library_and_native(qualifier+"/atomic_brand_colors.xml", f'<?xml version="1.0" encoding="utf-8"?>\n<resources><color name="atomic_splash_background">{color}</color></resources>\n')
    earlier = (f'<?xml version="1.0" encoding="utf-8"?>\n<layer-list xmlns:android="{ANDROID}">\n'
               '    <item android:drawable="@color/atomic_splash_background"/>\n'
               '    <item android:gravity="center" android:drawable="@drawable/atomic_splash_logo"/>\n</layer-list>\n')
    for qualifier in ("drawable", "drawable-v21"):
        library_and_native(qualifier+"/launch_background.xml", earlier)
    for qualifier, parent in (("values-v31", "Theme.Light.NoTitleBar"), ("values-night-v31", "Theme.Black.NoTitleBar")):
        style = ('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
                 f'    <style name="LaunchTheme" parent="@android:style/{parent}">\n'
                 '        <item name="android:windowBackground">@drawable/launch_background</item>\n'
                 '        <item name="android:windowSplashScreenBackground">@color/atomic_splash_background</item>\n'
                 '        <item name="android:windowSplashScreenAnimatedIcon">@drawable/atomic_splash_logo</item>\n'
                 '    </style>\n</resources>\n')
        library_and_native(qualifier+"/styles.xml", style)
    # Prepared for a future native notification feature; no channel or push SDK
    # is added. Deliberately simpler and thicker than the launcher at 24 dp.
    notification = (f'<?xml version="1.0" encoding="utf-8"?>\n<vector xmlns:android="{ANDROID}" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">\n'
                    '    <path android:pathData="M3,12a9,4 0,1 0,18,0a9,4 0,1 0,-18,0Z" android:fillColor="#00000000" android:strokeColor="#FFFFFFFF" android:strokeWidth="2"/>\n'
                    '    <group android:rotation="60" android:pivotX="12" android:pivotY="12"><path android:pathData="M3,12a9,4 0,1 0,18,0a9,4 0,1 0,-18,0Z" android:fillColor="#00000000" android:strokeColor="#FFFFFFFF" android:strokeWidth="2"/></group>\n'
                    '    <path android:pathData="M9.5,12a2.5,2.5 0,1 0,5,0a2.5,2.5 0,1 0,-5,0Z" android:fillColor="#FFFFFFFF"/>\n</vector>\n')
    library_and_native("drawable/atomic_notification.xml", notification)
    notify = Image.new("RGBA", (96,96), (0,0,0,0))
    draw = ImageDraw.Draw(notify)
    for rotation in (0,60):
        points=[]
        for i in range(361):
            theta=math.radians(i); angle=math.radians(rotation)
            x,y=36*math.cos(theta),16*math.sin(theta)
            points.append((48+x*math.cos(angle)-y*math.sin(angle),48+x*math.sin(angle)+y*math.cos(angle)))
        draw.line(points, fill="white", width=8, joint="curve")
    draw.ellipse((38,38,58,58),fill="white")
    for size in (24,36,48,72,96):
        save_png(LIB / "android/notification" / f"notification-{size}.png", notify.resize((size,size),Image.Resampling.LANCZOS))
    for name, fallback in (("devbehindyou-worker", "devbehindyou-worker-static"),
                           ("dotgrid-blink-transparent", "dotgrid-static")):
        with Image.open(ASSETS / "Atomic Icons" / (name+".gif")) as animation:
            frame = animation.convert("RGBA")
            # Exact decoded first frame, preserving original pixels and alpha.
            # Runtime Image.cacheWidth controls the decode size for the UI.
            save_png(LIB / "png" / (fallback+".png"),frame)
    preview()


def preview() -> None:
    board = Image.new("RGB", (1200,660), "#DFE2DC")
    draw=ImageDraw.Draw(board)
    labels=("Circle / White-purple", "Rounded / White-purple", "Previous / Dark", "Themed / light", "Themed / dark")
    for i,label in enumerate(labels):
        x=30+i*235
        bg=INK if i in (2,4) else LAUNCHER_WHITE
        # Android masks the 72 dp visible viewport of the 108 dp layer canvas;
        # the remaining 18 dp on each edge is reserved for parallax effects.
        radius=99 if i==2 else LAUNCHER_ADAPTIVE_RADIUS*3
        layer=raster("mono-white" if i==4 else "mono-ink" if i==3 else "on-dark" if i==2 else "launcher-white-purple",324,radius,bg,15 if i==2 else LAUNCHER_STROKE)
        icon=layer.crop((54,54,270,270))
        mask=Image.new("L",(216,216)); md=ImageDraw.Draw(mask)
        if i==1: md.rounded_rectangle((0,0,215,215),radius=48,fill=255)
        else: md.ellipse((0,0,215,215),fill=255)
        flattened=Image.alpha_composite(Image.new("RGBA",(216,216),rgba(bg)),icon)
        board.paste(flattened.convert("RGB"),(x,55),mask)
        draw.text((x,24),label,fill=INK)
    # Exact 108 dp / 66 dp adaptive and 288 dp / 192 dp native splash bounds.
    adaptive=raster("launcher-white-purple",324,LAUNCHER_ADAPTIVE_RADIUS*3,LAUNCHER_WHITE,LAUNCHER_STROKE)
    board.paste(adaptive.convert("RGB"),(44,305))
    draw.rectangle((44,305,367,628),outline="#555555",width=1)
    draw.ellipse((107,368,305,566),outline="#CE4A4A",width=2)
    draw.text((44,278),"Top: masks of central 72 dp viewport / 108 dp layers",fill=INK)
    draw.text((44,292),"Below: full layer; red circle = central 66 / 108 dp",fill=INK)
    splash=raster("on-dark",288,88,INK)
    board.paste(splash.convert("RGB"),(440,320))
    draw.ellipse((488,368,680,560),outline="#CE4A4A",width=2)
    draw.text((440,285),"Native splash: red circle = central 192 / 288 dp",fill=INK)
    draw.text((800,330),"Launcher: white / purple; 2/3 artwork",fill=INK)
    draw.text((800,356),"Actual launcher sizes: 48 px / 32 px",fill=INK)
    for i,size in enumerate((48,32)):
        layer=raster("launcher-white-purple",size*6,size*6*LAUNCHER_ADAPTIVE_RADIUS/108,LAUNCHER_WHITE,LAUNCHER_STROKE)
        visible=layer.crop((size,size,size*5,size*5)).resize((size,size),Image.Resampling.LANCZOS)
        mask=Image.new("L",(size,size)); ImageDraw.Draw(mask).ellipse((0,0,size-1,size-1),fill=255)
        board.paste(visible.convert("RGB"),(800+i*85,395),mask)
    draw.text((800,465),"Splash unchanged; source SVGs unchanged",fill=INK)
    save_png(LIB / "previews/android-masks-safe-zones.png",board)


def verify(provenance: dict) -> dict:
    for name, expected in SOURCE_HASHES.items():
        assert sha(ASSETS/name)==expected,"Named artwork or mascot source differs"
    for variant in VARIANTS:
        validate_vector(ET.parse(LIB/"svg"/f"atomic-icon-{variant}.svg").getroot(),variant)
    checked=[]
    for path in sorted(LIB.rglob("*")):
        if not path.is_file() or path.name in ("manifest.json","README.md"):
            continue
        row={"path":path.relative_to(ASSETS).as_posix(),"bytes":path.stat().st_size,"sha256":sha(path)}
        if path.suffix.lower() in (".png",".gif"):
            with Image.open(path) as image:
                row.update({"width":image.width,"height":image.height,"mode":image.mode,"frames":getattr(image,"n_frames",1)})
                if path.suffix==".png":
                    row["alphaRange"]=list(image.convert("RGBA").getchannel("A").getextrema())
        elif path.suffix in (".svg",".xml"):
            ET.parse(path)
        checked.append(row)
    foreground=Image.open(LIB/"android/adaptive-foreground.png").convert("RGBA")
    # LANCZOS's faint fringes are not important artwork. All alpha >= 128 pixels
    # stay inside 66 dp diameter (132 px radius at 4 px/dp), allowing 1 pixel AA.
    alpha=foreground.getchannel("A")
    max_radius=max(math.hypot(x+0.5-216,y+0.5-216) for y in range(432) for x in range(432) if alpha.getpixel((x,y))>=128)
    assert max_radius <= 133, "Adaptive artwork outside central safe circle"
    assert abs(max_radius-LAUNCHER_ADAPTIVE_RADIUS*4) <= 1, "Launcher artwork scale differs"
    monochrome=Image.open(LIB/"android/adaptive-monochrome.png").convert("RGBA")
    assert all(r==g==b==255 for r,g,b,a in list(monochrome.get_flattened_data()) if a), "Colored monochrome layer"
    store=Image.open(LIB/"android/google-play-512.png")
    assert store.size==(512,512) and store.mode=="RGBA" and store.getchannel("A").getextrema()==(255,255)
    assert (LIB/"android/google-play-512.png").stat().st_size < 1024*1024
    for library in (LIB/"android/native").rglob("*.xml"):
        assert library.read_bytes()==(RES/library.relative_to(LIB/"android/native")).read_bytes(), "Native/library drift"
    for name, fallback in (("devbehindyou-worker", "devbehindyou-worker-static"),
                           ("dotgrid-blink-transparent", "dotgrid-static")):
        with Image.open(ASSETS/"Atomic Icons"/(name+".gif")) as animation, Image.open(LIB/"png"/(fallback+".png")) as static:
            frame=animation.convert("RGBA")
            assert static.mode=="RGBA" and static.size==frame.size and static.tobytes()==frame.tobytes(),"Mascot fallback differs from first frame"
    return {"version":1,"supportedConfiguredReleasePlatforms":["android"],
            "artworkAuthority":"assets/atomic-icon.jpg (unchanged JPEG); supplied editable vector companion for transparent/native derivatives",
            "transparencyMethod":"audited supplied vector geometry; no JPEG extension rename, color-threshold removal or AI redraw",
            "visualBoundary":"Companion is a symmetric reconstruction, not pixel-identical JPEG extraction. On-dark intentionally substitutes Paper for Ink to preserve contrast.",
            "colors":{"paper":PAPER,"ink":INK,"signal":SIGNAL},
            "sources":provenance,"android":{"adaptiveCanvasDp":108,"adaptiveSafeDiameterDp":66,
            "launcher":{"variant":"white-purple","background":LAUNCHER_WHITE,"artworkColor":LAUNCHER_PURPLE,"orbitStrokeWidth":LAUNCHER_STROKE,"sourceOrbitStrokeWidth":11,
            "artworkScaleRelativeToPrevious":LAUNCHER_ARTWORK_SCALE,"adaptiveArtworkRadiusDp":LAUNCHER_ADAPTIVE_RADIUS,"rasterArtworkRadiusRatio":LAUNCHER_RASTER_RADIUS_RATIO},
            "measuredImportantArtworkMaxRadiusDp":round(max_radius/4,3),"nativeSplashCanvasDp":288,
            "nativeSplashSafeDiameterDp":192,"nativeSplashArtworkDiameterDp":176,
            "legacyPixels":[48,72,96,144,192],"play":{"pixels":512,"mode":"RGBA","maxBytes":1048576},
            "notification":"prepared simplified white-alpha resource; app currently has no native notification channel",
            "animation":"Native splash static vector. Supplied transparent GIFs animate the Flutter splash with exact first-frame reduced-motion fallbacks; no added startup hold."},
            "unverifiedPlatforms":["ios","macos","windows","linux","web"],"files":checked}


def main() -> None:
    parser=argparse.ArgumentParser()
    parser.add_argument("--import-source",type=Path)
    parser.add_argument("--verify-only",action="store_true")
    args=parser.parse_args()
    previous=LIB/"manifest.json"
    provenance=json.loads(previous.read_text(encoding="utf-8"))["sources"] if previous.exists() else {}
    if args.import_source:
        provenance=import_sources(args.import_source)
    if not args.verify_only:
        build()
    manifest=verify(provenance)
    if args.verify_only:
        stored=json.loads(previous.read_text(encoding="utf-8"))
        assert stored==manifest,"Generated manifest differs; regenerate intentionally"
    else:
        write(previous,json.dumps(manifest,indent=2,ensure_ascii=True)+"\n")
    print(json.dumps({"outcome":"passed","files":len(manifest["files"]),"adaptiveRadiusDp":manifest["android"]["measuredImportantArtworkMaxRadiusDp"],"platforms":["android"]}))


if __name__=="__main__":
    main()
