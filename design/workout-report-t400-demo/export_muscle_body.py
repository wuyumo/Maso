#!/usr/bin/env python3
"""Convert the app's MuscleBody.scn into a browser mesh.

The SceneKit file is the approved training model (see MuscleBodyLicense.txt).
This script does not redraw a body. High-poly landmark meshes are grid-decimated
so a phone browser can rotate the same named regions. Muscle silhouettes under
the cap are kept triangle-for-triangle.
"""

import base64
import json
import plistlib
import struct
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SCN = ROOT / "Maso/Resources/Anatomy/MuscleBody.scn"
OUT_DIR = Path(__file__).resolve().parent / "assets"
GLB = OUT_DIR / "muscle-body.glb"
JS = OUT_DIR / "muscle-body.js"

CAPS = {
    "head_center": 14000,
    "hands_left": 4500,
    "hands_right": 4500,
    "feet_left": 3200,
    "feet_right": 3200,
    "upperTraps_left": 9000,
    "upperTraps_right": 9000,
    "forearms_left": 6500,
    "forearms_right": 6500,
    "biceps_left": 4500,
    "biceps_right": 4500,
    "triceps_left": 5500,
    "triceps_right": 5500,
    "shoulders_left": 5000,
    "shoulders_right": 5000,
}


def deref(objs, value):
    if isinstance(value, plistlib.UID):
        return objs[int(value)]
    return value


def triangle_count(indices):
    return int(indices.shape[0])


def cluster(positions, indices, max_tris):
    if triangle_count(indices) <= max_tris:
        return positions, indices
    lo = positions.min(axis=0)
    span = float(np.max(positions.max(axis=0) - lo)) or 1.0
    left, right = span / 4000.0, span
    best = None
    for _ in range(18):
        cell = (left + right) / 2
        reduced_pos, reduced_idx = cluster_once(positions, indices, lo, cell)
        if triangle_count(reduced_idx) > max_tris:
            left = cell
        else:
            best = (reduced_pos, reduced_idx)
            right = cell
    return best if best is not None else cluster_once(positions, indices, lo, span / 8)


def cluster_once(positions, indices, origin, cell):
    keys = np.floor((positions - origin) / cell).astype(np.int32)
    buckets = {}
    sums = []
    counts = []
    remap = np.empty(len(positions), dtype=np.int32)
    for index, key in enumerate(map(tuple, keys)):
        slot = buckets.get(key)
        if slot is None:
            slot = len(sums)
            buckets[key] = slot
            sums.append(positions[index].astype(np.float64))
            counts.append(1)
        else:
            sums[slot] += positions[index]
            counts[slot] += 1
        remap[index] = slot
    reduced = np.stack([sums[i] / counts[i] for i in range(len(sums))]).astype(np.float32)
    mapped = remap[indices]
    keep = (mapped[:, 0] != mapped[:, 1]) & (mapped[:, 1] != mapped[:, 2]) & (mapped[:, 0] != mapped[:, 2])
    mapped = mapped[keep]
    order = np.argsort(mapped.min(axis=1))
    mapped = mapped[order]
    # Stable unique triangles, preserving the first winding.
    _, unique_index = np.unique(np.sort(mapped, axis=1), axis=0, return_index=True)
    mapped = mapped[np.sort(unique_index)]
    used, inverse = np.unique(mapped.reshape(-1), return_inverse=True)
    return reduced[used], inverse.astype(np.uint32).reshape(-1, 3)


def pad(blob, alignment=4):
    return blob + b"\x00" * ((alignment - len(blob) % alignment) % alignment)


def main():
    with SCN.open("rb") as handle:
        archive = plistlib.load(handle)
    objs = archive["$objects"]
    meshes = []
    report = []
    for obj in objs:
        if not (isinstance(obj, dict) and "name" in obj and "geometry" in obj):
            continue
        name = deref(objs, obj["name"])
        geometry = deref(objs, obj["geometry"])
        source = deref(objs, geometry["kGeometrySourceSemanticVertex"])
        source = deref(objs, source["NS.objects"][0])
        element = deref(objs, geometry["elements"])
        element = deref(objs, element["NS.objects"][0])
        vertices = np.frombuffer(deref(objs, source["data"]), dtype="<f4").reshape(-1, 3).copy()
        raw_index = np.frombuffer(deref(objs, element["elementData"]), dtype="<u4")
        triangles = raw_index.reshape(-1, 3).copy()
        before = len(triangles)
        positions, reduced = cluster(vertices, triangles, CAPS.get(name, 4000))
        meshes.append((name, positions, reduced))
        report.append((name, before, len(reduced), len(positions)))

    buffer = bytearray()
    primitives = []
    for name, positions, indices in meshes:
        pos_blob = positions.astype("<f4").tobytes()
        idx_type = "<u2" if len(positions) < 65536 else "<u4"
        idx_blob = indices.astype(idx_type).tobytes()
        pos_offset = len(buffer)
        buffer += pos_blob
        buffer = bytearray(pad(buffer))
        idx_offset = len(buffer)
        buffer += idx_blob
        buffer = bytearray(pad(buffer))
        primitives.append({
            "name": name,
            "pos": (pos_offset, len(pos_blob), positions.min(0).tolist(), positions.max(0).tolist(), len(positions)),
            "idx": (idx_offset, len(idx_blob), 5123 if idx_type == "<u2" else 5125, len(indices) * 3),
        })

    accessors = []
    views = []
    gltf_meshes = []
    nodes = []
    for prim in primitives:
        pos_view = len(views)
        views.append({"buffer": 0, "byteOffset": prim["pos"][0], "byteLength": prim["pos"][1], "target": 34962})
        idx_view = len(views)
        views.append({"buffer": 0, "byteOffset": prim["idx"][0], "byteLength": prim["idx"][1], "target": 34963})
        pos_acc = len(accessors)
        accessors.append({
            "bufferView": pos_view, "componentType": 5126, "count": prim["pos"][4],
            "type": "VEC3", "min": prim["pos"][2], "max": prim["pos"][3],
        })
        idx_acc = len(accessors)
        accessors.append({
            "bufferView": idx_view, "componentType": prim["idx"][2], "count": prim["idx"][3], "type": "SCALAR",
        })
        mesh_index = len(gltf_meshes)
        gltf_meshes.append({"name": prim["name"], "primitives": [{
            "attributes": {"POSITION": pos_acc}, "indices": idx_acc, "material": 0,
        }]})
        nodes.append({"name": prim["name"], "mesh": mesh_index})

    gltf = {
        "asset": {"version": "2.0", "generator": "Masso MuscleBody.scn browser export"},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(nodes)))}],
        "nodes": nodes,
        "meshes": gltf_meshes,
        "materials": [{"name": "muscle", "pbrMetallicRoughness": {"baseColorFactor": [0.24, 0.24, 0.24, 1], "metallicFactor": 0, "roughnessFactor": 0.84}, "doubleSided": True}],
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(buffer)}],
    }
    json_blob = json.dumps(gltf, separators=(",", ":")).encode()
    json_blob = pad(json_blob)
    bin_blob = pad(bytes(buffer))
    length = 12 + 8 + len(json_blob) + 8 + len(bin_blob)
    glb = b"glTF" + struct.pack("<II", 2, length)
    glb += struct.pack("<I4s", len(json_blob), b"JSON") + json_blob
    glb += struct.pack("<I4s", len(bin_blob), b"BIN\x00") + bin_blob
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    GLB.write_bytes(glb)

    payload = []
    for name, positions, indices in meshes:
        payload.append({
            "name": name,
            "position": base64.b64encode(positions.astype("<f4").tobytes()).decode(),
            "index": base64.b64encode(indices.astype("<u4").tobytes()).decode(),
        })
    JS.write_text("window.MUSCLE_BODY=" + json.dumps({"meshes": payload, "decimated": True}, separators=(",", ":")) + ";\n", encoding="utf-8")
    print(f"glb {GLB.stat().st_size} js {JS.stat().st_size}")
    for name, before, after, verts in report:
        print(f"{name:24} {before:7} -> {after:6} tris  {verts:6} verts")


if __name__ == "__main__":
    main()
