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
    controls=(valid_library,png_crc_corruption,adaptive_outside_safe_zone,colored_monochrome,
              transparent_store,wrong_legacy_size,native_monochrome_alias,source_asset_tamper,
              raw_exception_hidden,decode_bound,manifest_path_escape)
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
