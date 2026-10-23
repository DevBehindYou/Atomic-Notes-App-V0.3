"""Verify committed Android brand assets in CI without Pillow or installation.

Only bounded committed files are inspected. Console and proof contain a fixed
schema with no exception text, absolute paths or raw image/decoder diagnostics.
Generation and exact GIF-first-frame equivalence use the separate local tool.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys
import xml.etree.ElementTree as ET
import zlib

ROOT=Path(__file__).resolve().parents[1]
ASSETS=ROOT/"assets"
LIB=ASSETS/"new-atomic-icons"
RES=ROOT/"android/app/src/main/res"
A="{http://schemas.android.com/apk/res/android}"
SOURCES={
    "atomic-icon.jpg":"3114c97ad9fe8ce43d5760e9399be135c0a0a1608b528e3aab6f4155bfa546e9",
    "Atomic Icons/devbehindyou-worker.gif":"e5993ff1ada52aa281a720d0307d53a7cffccc48839cfccca142041b8783c96a",
    "Atomic Icons/dotgrid-blink-transparent.gif":"208a81c983c0060f4a16252e9fabf97353c272269f639c2c0134cdac6f119377",
}
CASE_CODES=("source_assets","library_integrity","adaptive_layers","android_launcher",
            "native_splash","store_icon","mascots","notification","white_purple_launcher_style")
MAX_FILE=8*1024*1024
MAX_DECODED=16*1024*1024


def bounded(path: Path) -> bytes:
    if path.stat().st_size>MAX_FILE:
        raise ValueError("file bound")
    data=path.read_bytes()
    if len(data)>MAX_FILE:
        raise ValueError("file bound")
    return data


def png(path: Path) -> tuple[int,int,bytes,bool]:
    data=bounded(path)
    if data[:8]!=b"\x89PNG\r\n\x1a\n":
        raise ValueError("PNG signature")
    pos=8; compressed=bytearray(); header=None; srgb=False; end=False
    while pos<len(data):
        if pos+12>len(data):
            raise ValueError("PNG chunk length")
        length=struct.unpack_from(">I",data,pos)[0]
        kind=data[pos+4:pos+8]; payload=data[pos+8:pos+8+length]
        if pos+12+length>len(data) or zlib.crc32(kind+payload)&0xffffffff!=struct.unpack_from(">I",data,pos+8+length)[0]:
            raise ValueError("PNG chunk integrity")
        if kind==b"IHDR":
            if header is not None or pos!=8 or length!=13:
                raise ValueError("PNG header")
            header=struct.unpack(">IIBBBBB",payload)
        elif kind==b"sRGB":
            if payload!=b"\x00" or srgb:
                raise ValueError("PNG sRGB")
            srgb=True
        elif kind==b"IDAT":
            compressed.extend(payload)
        elif kind==b"IEND":
            if length!=0 or pos+12!=len(data):
                raise ValueError("PNG end")
            end=True
        pos+=12+length
    if header is None or not end:
        raise ValueError("PNG completeness")
    width,height,bits,color,compression,filtering,interlace=header
    if not (0<width<=2048 and 0<height<=2048) or (bits,color,compression,filtering,interlace)!=(8,6,0,0,0):
        raise ValueError("PNG RGBA format")
    stride=width*4; expected=(stride+1)*height
    if expected>MAX_DECODED:
        raise ValueError("PNG decode bound")
    decoder=zlib.decompressobj()
    rows=decoder.decompress(compressed,expected+1)
    if len(rows)!=expected or not decoder.eof or decoder.unconsumed_tail or decoder.unused_data:
        raise ValueError("PNG decoded length")
    previous=bytearray(stride); pixels=bytearray(stride*height)
    for y in range(height):
        start=y*(stride+1); mode=rows[start]
        row=bytearray(rows[start+1:start+1+stride])
        if mode not in (0,1,2,3,4):
            raise ValueError("PNG filter")
        for i in range(stride):
            left=row[i-4] if i>=4 else 0
            up=previous[i]
            upper_left=previous[i-4] if i>=4 else 0
            if mode==1: predictor=left
            elif mode==2: predictor=up
            elif mode==3: predictor=(left+up)//2
            elif mode==4:
                base=left+up-upper_left
                distances=(abs(base-left),abs(base-up),abs(base-upper_left))
                predictor=left if distances[0]<=min(distances[1:]) else up if distances[1]<=distances[2] else upper_left
            else: predictor=0
            row[i]=(row[i]+predictor)&255
        pixels[y*stride:(y+1)*stride]=row
        previous=row
    return width,height,bytes(pixels),srgb


def source_assets() -> None:
    for name,expected in SOURCES.items():
        assert hashlib.sha256(bounded(ASSETS/name)).hexdigest()==expected


def library_integrity() -> None:
    manifest=json.loads(bounded(LIB/"manifest.json"))
    assert manifest["version"]==1 and manifest["supportedConfiguredReleasePlatforms"]==["android"]
    assert len(manifest["files"])==44
    names=set()
    for file in manifest["files"]:
        path=Path(file["path"])
        assert not path.is_absolute() and ".." not in path.parts and path.parts[0]=="new-atomic-icons"
        assert file["path"] not in names
        names.add(file["path"])
        data=bounded(ASSETS/path)
        assert len(data)==file["bytes"] and hashlib.sha256(data).hexdigest()==file["sha256"]
    assert {p.relative_to(ASSETS).as_posix() for p in LIB.rglob("*") if p.is_file() and p.name not in ("manifest.json","README.md")}==names
    for library in (LIB/"android/native").rglob("*.xml"):
        content=bounded(library)
        ET.fromstring(content)
        assert content==bounded(RES/library.relative_to(LIB/"android/native"))
    for vector in (LIB/"svg").glob("*.svg"):
        root=ET.fromstring(bounded(vector))
        assert all(node.tag.rsplit("}",1)[-1] in ("svg","g","ellipse","circle","path") for node in root.iter())


def radius_check(path: Path, size: int, max_radius: float) -> bytes:
    width,height,pixels,_=png(path)
    assert (width,height)==(size,size)
    visible=False
    for i in range(0,len(pixels),4):
        if pixels[i+3]>=128:
            visible=True
            pixel=i//4
            assert math.hypot(pixel%size+.5-size/2,pixel//size+.5-size/2)<=max_radius+1
    assert visible and min(pixels[3::4])==0 and max(pixels[3::4])==255
    return pixels


def adaptive_layers() -> None:
    radius_check(LIB/"android/adaptive-foreground.png",432,132)
    pixels=radius_check(LIB/"android/adaptive-monochrome.png",432,132)
    assert all(pixels[i:i+3]==b"\xff\xff\xff" for i in range(0,len(pixels),4) if pixels[i+3])
    for name in ("atomic_launcher_foreground","atomic_launcher_monochrome"):
        root=ET.fromstring(bounded(RES/"drawable"/(name+".xml")))
        assert root.tag=="vector" and root.get(A+"viewportWidth")=="108" and root.get(A+"viewportHeight")=="108"
        assert root.get(A+"width")=="108dp" and root.get(A+"height")=="108dp"
        group=root.find("group")
        assert group is not None and group.get(A+"translateX")=="54" and group.get(A+"translateY")=="54"
        assert abs(float(group.get(A+"scaleX","0"))*362-22)<.00001
        assert group.get(A+"scaleX")==group.get(A+"scaleY")
    mono=ET.fromstring(bounded(RES/"drawable/atomic_launcher_monochrome.xml"))
    colors={node.get(A+key) for node in mono.iter() for key in ("fillColor","strokeColor") if node.get(A+key) is not None}
    assert colors=={"#FFFFFF","#00000000"}
    assert any(node.get(A+"fillType")=="evenOdd" for node in mono.iter())


def android_launcher() -> None:
    for name in ("launcher_icon","ic_launcher"):
        node=ET.fromstring(bounded(RES/"mipmap-anydpi-v26"/(name+".xml")))
        assert node.tag=="adaptive-icon"
        assert {child.tag:child.get(A+"drawable") for child in node}=={
            "background":"@color/ic_launcher_background","foreground":"@drawable/atomic_launcher_foreground","monochrome":"@drawable/atomic_launcher_monochrome"}
    for density,size in (("mdpi",48),("hdpi",72),("xhdpi",96),("xxhdpi",144),("xxxhdpi",192)):
        for name in ("launcher_icon","ic_launcher"):
            width,height,pixels,_=png(RES/("mipmap-"+density)/(name+".png"))
            assert (width,height)==(size,size) and set(pixels[3::4])=={255}
            assert bounded(RES/("mipmap-"+density)/(name+".png"))==bounded(LIB/"android/legacy"/("launcher-"+str(size)+".png"))
    manifest=ET.fromstring(bounded(ROOT/"android/app/src/main/AndroidManifest.xml"))
    assert manifest.find("application").get(A+"icon")=="@mipmap/launcher_icon"


def native_splash() -> None:
    for qualifier,variant in (("drawable","on-light"),("drawable-night","on-dark")):
        node=ET.fromstring(bounded(RES/qualifier/"atomic_splash_logo.xml"))
        assert node.get(A+"viewportWidth")=="288" and node.get(A+"viewportHeight")=="288"
        group=node.find("group")
        assert group is not None and group.get(A+"translateX")=="144" and group.get(A+"translateY")=="144"
        assert abs(float(group.get(A+"scaleX","0"))*362-88)<.00001 and group.get(A+"scaleX")==group.get(A+"scaleY")
        radius_check(LIB/"splash"/("atomic-splash-"+variant+".png"),576,192)
    for qualifier in ("values-v31","values-night-v31"):
        styles=ET.fromstring(bounded(RES/qualifier/"styles.xml"))
        items={node.get("name"):node.text for node in styles.find("style")}
        assert items=={"android:windowBackground":"@drawable/launch_background",
                       "android:windowSplashScreenBackground":"@color/atomic_splash_background",
                       "android:windowSplashScreenAnimatedIcon":"@drawable/atomic_splash_logo"}
    for qualifier in ("drawable","drawable-v21"):
        background=ET.fromstring(bounded(RES/qualifier/"launch_background.xml"))
        assert [child.get(A+"drawable") for child in background]==["@color/atomic_splash_background","@drawable/atomic_splash_logo"]


def store_icon() -> None:
    path=LIB/"android/google-play-512.png"
    width,height,pixels,srgb=png(path)
    assert (width,height)==(512,512) and len(bounded(path))<1024*1024 and srgb and set(pixels[3::4])=={255}


def white_purple_launcher_style() -> None:
    # Pin current visible intent independently of generated hashes and manifest.
    white=b"\xff\xff\xff\xff"
    for relative in ("android/google-play-512.png", "android/launcher-source-1024.png",
                     "android/legacy/launcher-48.png"):
        _,_,pixels,_=png(LIB/relative)
        assert pixels[:4]==white
    colors=ET.fromstring(bounded(RES/"values/ic_launcher_background.xml"))
    assert colors.find("color").text=="#FFFFFF"
    config=bounded(ROOT/"pubspec.yaml").decode("utf-8")
    assert 'adaptive_icon_background: "#FFFFFF"' in config
    for name in ("atomic_launcher_foreground", "atomic_launcher_monochrome"):
        root=ET.fromstring(bounded(RES/"drawable"/(name+".xml")))
        orbits=[node for node in root.iter("path") if node.get(A+"strokeWidth")]
        assert len(orbits)==3 and all(node.get(A+"strokeWidth")=="24" for node in orbits)
        if name=="atomic_launcher_foreground":
            assert [node.get(A+"strokeColor") for node in orbits]==["#4B238C"]*3
            fills=[node.get(A+"fillColor") for node in root.iter("path") if not node.get(A+"strokeWidth")]
            assert fills==["#4B238C"]*4+["#FFFFFF"]
    _,_,foreground,_=png(LIB/"android/adaptive-foreground.png")
    # Check solid raster interiors as well as native vector colors; AA boundary
    # pixels may blend purple into the white nucleus, so do not ban those blends.
    opaque={foreground[i:i+3] for i in range(0,len(foreground),4) if foreground[i+3]==255}
    assert b"\x4b\x23\x8c" in opaque and b"\xff\xff\xff" in opaque
    assert b"\x3a\x2f\xf0" not in opaque and b"\xf4\xf5\xf1" not in opaque
    # Measure actual artwork independently of generated hashes and metadata.
    # Alpha identifies transparent artwork; opaque tiles use solid purple cores.
    paths=[LIB/"android"/name for name in ("adaptive-foreground.png", "adaptive-monochrome.png",
                                         "google-play-512.png", "launcher-source-1024.png")]
    paths.extend(sorted((LIB/"android/legacy").glob("launcher-*.png")))
    for path in paths:
        size,height,pixels,_=png(path)
        assert size==height
        transparent="adaptive-" in path.name
        radii=[]
        for i in range(0,len(pixels),4):
            if pixels[i+3]>=128 and (transparent or all(abs(pixels[i+j]-color)<=32 for j,color in enumerate((75,35,140)))):
                pixel=i//4
                radii.append(math.hypot(pixel%size+.5-size/2,pixel//size+.5-size/2))
        expected=88 if transparent else size*.28
        assert radii and abs(max(radii)-expected)<=1.5


def mascots() -> None:
    for name,size in (("devbehindyou-worker-static",(1285,1285)),("dotgrid-static",(400,480))):
        width,height,pixels,_=png(LIB/"png"/(name+".png"))
        assert (width,height)==size and min(pixels[3::4])==0 and max(pixels[3::4])==255


def notification() -> None:
    node=ET.fromstring(bounded(RES/"drawable/atomic_notification.xml"))
    assert node.get(A+"width")=="24dp" and node.get(A+"height")=="24dp"
    colors={child.get(A+key) for child in node.iter() for key in ("fillColor","strokeColor") if child.get(A+key) is not None}
    assert colors=={"#FFFFFFFF","#00000000"}
    for size in (24,36,48,72,96):
        width,height,pixels,_=png(LIB/"android/notification"/("notification-"+str(size)+".png"))
        assert (width,height)==(size,size) and min(pixels[3::4])==0 and max(pixels[3::4])==255
        assert all(pixels[i:i+3]==b"\xff\xff\xff" for i in range(0,len(pixels),4) if pixels[i+3])


def run() -> dict:
    cases={}
    for code in CASE_CODES:
        try:
            globals()[code]()
            cases[code]="pass"
        except Exception:
            # Deliberately no error text, traceback, decoder stream or file paths.
            cases[code]="fail"
    good=all(value=="pass" for value in cases.values())
    return {"version":1,"scope":"committed Android branding assets; no device or release claim",
            "phase":"complete" if good else "verification","outcome":"pass" if good else "fail","cases":cases}


def main() -> None:
    parser=argparse.ArgumentParser()
    parser.add_argument("--proof",type=Path)
    args=parser.parse_args()
    proof=run()
    if args.proof:
        args.proof.parent.mkdir(parents=True,exist_ok=True)
        args.proof.write_text(json.dumps(proof,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(proof))
    sys.exit(0 if proof["outcome"]=="pass" else 1)


if __name__=="__main__":
    main()
