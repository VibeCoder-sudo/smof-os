# smof_embed : sentence embeddings with numpy and sentencepiece only (multilingual-e5-small, 384 numbers per text).
# the model file comes from convert_e5.py. Texts for search use the prefixes "query: " and "passage: " as the model expects.
import numpy as np, os

MODEL_DIR = os.environ.get("SMOF_MODEL_DIR", "/usr/share/smof/models/e5-small")
H, NH, EPS = 384, 12, 1e-12

class Embedder:
    def __init__(self, d=MODEL_DIR):
        import sentencepiece as spm
        self.sp = spm.SentencePieceProcessor(model_file=os.path.join(d, "sentencepiece.bpe.model"))
        z = np.load(os.path.join(d, "model.npz"))
        self.wq, self.ws = z["word_q"], z["word_s"].astype(np.float32)
        g = lambda k: z[k.replace(".", "__")].astype(np.float32)
        self.pos, self.typ = g("embeddings.position_embeddings.weight"), g("embeddings.token_type_embeddings.weight")
        self.eg, self.eb = g("embeddings.LayerNorm.weight"), g("embeddings.LayerNorm.bias")
        self.L = []
        for i in range(12):
            p = "encoder.layer.%d." % i
            qkv_w = np.concatenate([g(p + "attention.self.%s.weight" % n) for n in ("query", "key", "value")], 0)
            qkv_b = np.concatenate([g(p + "attention.self.%s.bias" % n) for n in ("query", "key", "value")], 0)
            self.L.append((qkv_w.T.copy(), qkv_b, g(p + "attention.output.dense.weight").T.copy(), g(p + "attention.output.dense.bias"),
                           g(p + "attention.output.LayerNorm.weight"), g(p + "attention.output.LayerNorm.bias"),
                           g(p + "intermediate.dense.weight").T.copy(), g(p + "intermediate.dense.bias"),
                           g(p + "output.dense.weight").T.copy(), g(p + "output.dense.bias"),
                           g(p + "output.LayerNorm.weight"), g(p + "output.LayerNorm.bias")))

    def ids(self, text, maxlen=128):
        out = [0]
        for p in self.sp.encode(text, out_type=str):
            i = self.sp.piece_to_id(p)
            out.append(i + 1 if i != 0 else 3)
        out = out[:maxlen - 1] + [2]
        return out

    @staticmethod
    def _ln(x, g, b):
        m = x.mean(-1, keepdims=True); v = ((x - m) ** 2).mean(-1, keepdims=True)
        return (x - m) / np.sqrt(v + EPS) * g + b

    def one(self, text):
        ids = np.array(self.ids(text)); n = len(ids)
        x = self.wq[ids].astype(np.float32) * self.ws[ids][:, None] + self.pos[np.arange(n) + 2] + self.typ[0]
        x = self._ln(x, self.eg, self.eb)
        for qkv_w, qkv_b, ow, ob, ag, ab, iw, ib, fw, fb, fg, fbb in self.L:
            qkv = x @ qkv_w + qkv_b
            q, k, v = (qkv[:, j * H:(j + 1) * H].reshape(n, NH, 32).transpose(1, 0, 2) for j in range(3))
            a = q @ k.transpose(0, 2, 1) / np.sqrt(32.0)
            a = np.exp(a - a.max(-1, keepdims=True)); a /= a.sum(-1, keepdims=True)
            c = (a @ v).transpose(1, 0, 2).reshape(n, H)
            x = self._ln(x + c @ ow + ob, ag, ab)
            h = x @ iw + ib
            h = 0.5 * h * (1.0 + np.tanh(0.7978845608 * (h + 0.044715 * h ** 3)))   # gelu
            x = self._ln(x + h @ fw + fb, fg, fbb)
        e = x.mean(0)
        return e / (np.linalg.norm(e) + 1e-12)

    def embed(self, texts, prefix="passage: "):
        return np.stack([self.one(prefix + t) for t in texts]).astype(np.float32)
