"""Failure controls for the branding verifier; in-memory mutations, no asset writes."""
import json
from pathlib import Path
import struct
from unittest.mock import patch
import zlib

import verify_branding_assets as verifier


def chunk(kind: bytes, payload: bytes) -> bytes:
    return struct.pack(">I",len(payload))+kind+payload+struct.pack(">I",zlib.crc32(kind+payload)&0xffffffff)


def png(width: int,height: int,pixels: bytes) -> bytes:
    rows=b"".join(b"\x00"+pixels[y*width*4:(y+1)*width*4] for y in range(height))
    return (b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",width,height,8,6,0,0,0))
            +chunk(b"sRGB",b"\x00")+chunk(b"IDAT",zlib.compress(rows))+chunk(b"IEND",b""))


def substitution(target: Path, payload: bytes, failed_case: str) -> None:
    original=verifier.bounded
    with patch.object(verifier,"bounded",side_effect=lambda path:payload if path==target else original(path)):
        proof=verifier.run()
    assert proof["cases"][failed_case]=="fail"
    assert proof["outcome"]=="fail" and proof["phase"]=="verification"
    assert set(proof)=={"version","scope","phase","outcome","cases"}
    assert set(proof["cases"])==set(verifier.CASE_CODES)
    assert set(proof["cases"].values())<={"pass","fail"}


def valid_library() -> None:
    proof=verifier.run()
    assert proof["outcome"]=="pass" and proof["phase"]=="complete"


def launcher_is_two_thirds() -> None:
    for name in ("atomic_launcher_foreground", "atomic_launcher_monochrome"):
        root=verifier.ET.fromstring(verifier.bounded(verifier.RES/"drawable"/(name+".xml")))
        assert abs(float(root.find("group").get(verifier.A+"scaleX"))*362-22)<.00001
    for relative in ("android/adaptive-foreground.png", "android/adaptive-monochrome.png"):
        size,_,pixels,_=verifier.png(verifier.LIB/relative)
        radii=[verifier.math.hypot(i//4%size+.5-size/2,i//4//size+.5-size/2)
               for i in range(0,len(pixels),4) if pixels[i+3]>=128]
        assert 87<=max(radii)<=89


def old_full_size_vector() -> None:
    path=verifier.RES/"drawable/atomic_launcher_foreground.xml"
    root=verifier.ET.fromstring(verifier.bounded(path))
    scale=root.find("group").get(verifier.A+"scaleX").encode()
    substitution(path,verifier.bounded(path).replace(scale,b"0.091160221"),"adaptive_layers")


def old_full_size_raster(relative: str) -> None:
    path=verifier.LIB/relative
    width,height,raw,_=verifier.png(path)
    # Recreate a 150% centered version in memory with no Pillow dependency.
    pixels=bytearray(len(raw))
    for y in range(height):
        source_y=int((y+.5-height/2)/1.5+height/2)
        for x in range(width):
            source_x=int((x+.5-width/2)/1.5+width/2)
            source=(source_y*width+source_x)*4
            target=(y*width+x)*4
            pixels[target:target+4]=raw[source:source+4]
    substitution(path,png(width,height,pixels),"white_purple_launcher_style")


def old_full_size_adaptive() -> None:
    old_full_size_raster("android/adaptive-foreground.png")


def old_full_size_legacy() -> None:
    old_full_size_raster("android/legacy/launcher-48.png")


def old_full_size_store() -> None:
    old_full_size_raster("android/google-play-512.png")


def png_crc_corruption() -> None:
    path=verifier.LIB/"android/google-play-512.png"
    data=bytearray(verifier.bounded(path)); data[40]^=1
    substitution(path,bytes(data),"store_icon")


def adaptive_outside_safe_zone() -> None:
    path=verifier.LIB/"android/adaptive-foreground.png"
    w,h,raw,_=verifier.png(path)
    pixels=bytearray(raw); pixels[:4]=b"\xff\xff\xff\xff"
    substitution(path,png(w,h,pixels),"adaptive_layers")


def colored_monochrome() -> None:
    path=verifier.LIB/"android/adaptive-monochrome.png"
    w,h,raw,_=verifier.png(path); pixels=bytearray(raw)
    for i in range(0,len(pixels),4):
        if pixels[i+3]:
            pixels[i:i+3]=b"\x3a\x2f\xf0"
            break
    substitution(path,png(w,h,pixels),"adaptive_layers")


def transparent_store() -> None:
    path=verifier.LIB/"android/google-play-512.png"
    w,h,raw,_=verifier.png(path); pixels=bytearray(raw); pixels[3]=0
    substitution(path,png(w,h,pixels),"store_icon")


def wrong_launcher_background() -> None:
    path=verifier.RES/"values/ic_launcher_background.xml"
    substitution(path,verifier.bounded(path).replace(b"#FFFFFF",b"#15171B"),"white_purple_launcher_style")


def thin_launcher_orbits() -> None:
    path=verifier.RES/"drawable/atomic_launcher_foreground.xml"
    substitution(path,verifier.bounded(path).replace(b'strokeWidth="24"',b'strokeWidth="15"'),"white_purple_launcher_style")


def wrong_launcher_purple() -> None:
    path=verifier.RES/"drawable/atomic_launcher_foreground.xml"
    substitution(path,verifier.bounded(path).replace(b"#4B238C",b"#3A2FF0"),"white_purple_launcher_style")


def wrong_legacy_size() -> None:
    path=verifier.RES/"mipmap-mdpi/launcher_icon.png"
    substitution(path,png(49,49,b"\xff\xff\xff\xff"*(49*49)),"android_launcher")


def native_monochrome_alias() -> None:
    path=verifier.RES/"mipmap-anydpi-v26/launcher_icon.xml"
    payload=verifier.bounded(path).replace(b"@drawable/atomic_launcher_monochrome",b"@drawable/atomic_launcher_foreground")
    substitution(path,payload,"android_launcher")


def source_asset_tamper() -> None:
    path=verifier.ASSETS/"atomic-icon.jpg"
    data=bytearray(verifier.bounded(path)); data[0]^=1
    substitution(path,bytes(data),"source_assets")


def raw_exception_hidden() -> None:
    marker="PRIVATE_DIAGNOSTIC_MUST_NOT_ESCAPE"
    with patch.object(verifier,"store_icon",side_effect=ValueError(marker)):
        proof=verifier.run()
    assert proof["cases"]["store_icon"]=="fail" and marker not in json.dumps(proof)
    assert set(proof)=={"version","scope","phase","outcome","cases"}


def decode_bound() -> None:
    path=verifier.LIB/"android/google-play-512.png"
    payload=(b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",2048,2048,8,6,0,0,0))
             +chunk(b"IDAT",zlib.compress(b"\x00"*1024))+chunk(b"IEND",b""))
    substitution(path,payload,"store_icon")


def manifest_path_escape() -> None:
    path=verifier.LIB/"manifest.json"
    manifest=json.loads(verifier.bounded(path)); manifest["files"][0]["path"]="new-atomic-icons/../../escape.png"
    original=verifier.bounded
    seen=[]
    def read(candidate):
        seen.append(candidate)
        return json.dumps(manifest).encode() if candidate==path else original(candidate)
    with patch.object(verifier,"bounded",side_effect=read):
        proof=verifier.run()
    assert proof["cases"]["library_integrity"]=="fail"
    assert not any(".." in candidate.parts for candidate in seen)


def main() -> None:
    controls=(valid_library,launcher_is_two_thirds,png_crc_corruption,adaptive_outside_safe_zone,colored_monochrome,
              transparent_store,wrong_legacy_size,native_monochrome_alias,source_asset_tamper,
              raw_exception_hidden,decode_bound,manifest_path_escape,
              wrong_launcher_background,thin_launcher_orbits,wrong_launcher_purple,
              old_full_size_vector,old_full_size_adaptive,old_full_size_legacy,old_full_size_store)
    outcomes={}
    for control in controls:
        try:
            control()
            outcomes[control.__name__]="pass"
        except Exception:
            outcomes[control.__name__]="fail"
    good=all(value=="pass" for value in outcomes.values())
    print(json.dumps({"version":1,"scope":"branding verifier in-memory failure controls",
                      "outcome":"pass" if good else "fail","cases":outcomes}))
    raise SystemExit(0 if good else 1)


if __name__=="__main__":
    main()
