#!/usr/bin/env python3
# converts intfloat/multilingual-e5-small (safetensors) into one small npz that smof_embed.py runs with numpy only.
# word embeddings become int8 with one scale per row, everything else float16.
import json, struct, sys, numpy as np
src, out = sys.argv[1], sys.argv[2]
with open(src, "rb") as f:
    n = struct.unpack("<Q", f.read(8))[0]
    hdr = json.loads(f.read(n)); base = 8 + n
    DT = {"F32": np.float32, "F16": np.float16, "I64": np.int64}
    W = {}
    for k, v in hdr.items():
        if k == "__metadata__": continue
        s, e = v["data_offsets"]; f.seek(base + s)
        a = np.frombuffer(f.read(e - s), dtype=DT[v["dtype"]]).reshape(v["shape"])
        W[k[6:] if k.startswith("model.") else k] = a.astype(np.float32)
o = {}
we = W.pop("embeddings.word_embeddings.weight")
sc = np.abs(we).max(axis=1) / 127.0; sc[sc == 0] = 1.0
o["word_q"] = np.round(we / sc[:, None]).astype(np.int8); o["word_s"] = sc.astype(np.float16)
for k, a in W.items():
    if k.endswith("position_ids") or a.dtype.kind != "f": continue
    o[k.replace(".", "__")] = a.astype(np.float16)
np.savez(out, **o)
print("saved", out, len(o), "arrays")
