"""Convert the Sound comparison phone models to Core ML for Ichido.

Run by scripts/setup-sound-comparison.sh inside a temporary uv environment:

    python convert.py <lite|full> <output-dir> <zipa-source-dir>

Downloads the original weights from Hugging Face at pinned revisions, converts them exactly as
the lab did for engine version eng_r3, and writes into <output-dir>:

    zipa.mlpackage     ZIPA small CR-CTC, fp16, fixed 10 s fbank window with a padding mask
    hubert8.mlpackage  HuBERT-base ARPAbet CTC, int8 weights, exact length 1-30 s   (full only)
    xlsr8.mlpackage    wav2vec2 XLSR-53 eSpeak CTC, int8 weights, exact length 1-30 s (full only)
    <model>-vocab.json {"blank": n, "tokens": [...]} CTC vocabulary of each model
    <model>-substitutions.json  restricted substitution table of each model (full only), copied
                       from tools/sound-comparison/substitutions/ (lab eng_r3 golden/rps_allowed_*)
    manifest.json      engine id and version, models, sizes, sources

Every package outputs raw logits (no log-softmax) and one hidden layer. The app does the
log-softmax in Double. ZIPA's `hidden` is its encoder output, used by the word DTW (eng_r3).
"""

from __future__ import annotations

import json
import os
import shutil
import sys
import types
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn

ENGINE_VERSION = "eng_r3"
ENGINE_MODELS = {"lite": ["zipa"], "full": ["zipa", "hubert8", "xlsr8"]}
# Engines whose GOP-SF denominator uses the restricted substitution set (eng_r3 RPS).
RESTRICTED_SUBSTITUTIONS = {"full"}
SUBSTITUTIONS_DIR = Path(__file__).resolve().parent / "substitutions"

ZIPA_REPO, ZIPA_REVISION = "anyspeech/zipa-small-crctc-500k", "dfe87c97662606fa6db90ad06f627d4363314744"
ZIPA_CHECKPOINT = "zipa_small_crctc_500000_avg10.pth"
W2V = {
    "hubert8": ("Peacockery/hubert-base-phoneme-en", "132c3327b3150dc081f14035e1d31adb6db5074a"),
    "xlsr8": ("facebook/wav2vec2-xlsr-53-espeak-cv-ft", "2c733782da5604684829819a5eb744c193fe9398"),
}
LICENCES = {"zipa": "weights CC BY 4.0, code MIT", "hubert8": "Apache-2.0", "xlsr8": "Apache-2.0"}
ZIPA_WINDOW = 1000  # fbank frames (10 s)

import coremltools as ct  # noqa: E402
from coremltools.converters.mil import Builder as mb  # noqa: E402
from coremltools.converters.mil.frontend.torch.ops import _get_inputs  # noqa: E402
from coremltools.converters.mil.frontend.torch.torch_op_registry import register_torch_op  # noqa: E402


@register_torch_op
def logaddexp(context, node):  # Zipformer's Swoosh activations; coremltools 9 has no converter
    a, b = _get_inputs(context, node, expected=2)
    mx = mb.maximum(x=a, y=b)
    sp = mb.softplus(x=mb.mul(x=mb.abs(x=mb.sub(x=a, y=b)), y=-1.0))
    context.add(mb.add(x=mx, y=sp, name=node.name))


def convert(traced, inputs):
    return ct.convert(
        traced, inputs=inputs, outputs=[ct.TensorType(name="logits"), ct.TensorType(name="hidden")],
        compute_precision=ct.precision.FLOAT16, minimum_deployment_target=ct.target.macOS15,
        convert_to="mlprogram", skip_model_load=True)


# ---------------------------------------------------------------- ZIPA


def zipa_package(src: Path):
    """ZIPA small with a `length` input that masks the padding of the 10 s window."""
    k2 = types.ModuleType("k2")  # only used for fused Swoosh activations
    k2.swoosh_l = k2.swoosh_l_forward = lambda x: torch.logaddexp(torch.zeros_like(x), x - 4.0) - 0.08 * x - 0.035
    k2.swoosh_r = k2.swoosh_r_forward = lambda x: torch.logaddexp(torch.zeros_like(x), x - 1.0) - 0.08 * x - 0.313261687
    sys.modules["k2"] = k2
    sys.path.insert(0, str(src / "zipformer_crctc"))
    import zipformer
    from scaling import ScheduledFloat
    from scaling_converter import convert_scaled_to_non_scaled
    from subsampling import Conv2dSubsampling
    from huggingface_hub import hf_hub_download

    def ints(s):
        return tuple(int(v) for v in s.split(","))

    class ZipaCTC(nn.Module):
        def __init__(self):
            super().__init__()
            dims = ints("192,256,384,512,384,256")
            self.encoder_embed = Conv2dSubsampling(80, dims[0], dropout=ScheduledFloat((0.0, 0.3), (20000.0, 0.1)))
            self.encoder = zipformer.Zipformer2(
                output_downsampling_factor=1, downsampling_factor=ints("1,2,4,8,4,2"),
                num_encoder_layers=ints("2,2,3,4,3,2"), encoder_dim=dims,
                encoder_unmasked_dim=ints("192,192,256,256,256,192"), query_head_dim=ints("32"),
                pos_head_dim=ints("4"), value_head_dim=ints("12"), pos_dim=48, num_heads=ints("4,4,4,8,4,4"),
                feedforward_dim=ints("512,768,1024,1536,1024,768"), cnn_module_kernel=ints("31,31,15,15,15,31"),
                dropout=ScheduledFloat((0.0, 0.3), (20000.0, 0.1)), warmup_batches=4000.0, causal=False,
                chunk_size=ints("16,32,64,-1"), left_context_frames=ints("64,128,256,-1"))
            self.ctc_output = nn.Sequential(nn.Dropout(p=0.1), nn.Linear(512, 127), nn.LogSoftmax(dim=-1))

    def downsample(self, src):  # trace-friendly SimpleDownsample: repeat the last frame, then slice
        seq_len, batch, channels = src.shape
        ds = int(self.downsample)
        if ds == 1:
            return src * self.bias.softmax(dim=0)[0]
        n = (seq_len + ds - 1) // ds
        src = torch.cat((src, src[-1:].repeat(ds - 1, 1, 1)), dim=0)[: n * ds].reshape(-1, ds, batch, channels)
        return (src * self.bias.softmax(dim=0).unsqueeze(-1).unsqueeze(-1)).sum(dim=1)

    class Masked(nn.Module):
        def __init__(self, z):
            super().__init__()
            self.z, self.head = z, z.ctc_output[1]

        def forward(self, fbank, length):
            full = torch.ones_like(fbank[:, :, 0]).sum(1).to(torch.int64)
            x, _ = self.z.encoder_embed(fbank, full)
            lens = (length.to(torch.int64) - 7) // 2
            mask = torch.arange(x.shape[1], device=x.device)[None, :] >= lens[:, None]
            enc, _ = self.z.encoder(x.permute(1, 0, 2), lens, mask)
            enc = enc.permute(1, 0, 2)
            return self.head(enc), enc

    state = torch.load(hf_hub_download(ZIPA_REPO, ZIPA_CHECKPOINT, revision=ZIPA_REVISION),
                       map_location="cpu", weights_only=False)
    state = state.get("model", state)
    model = ZipaCTC()
    missing, _ = model.load_state_dict(
        {k: v for k, v in state.items() if k.split(".")[0] in ("encoder_embed", "encoder", "ctc_output")}, strict=False)
    if missing:
        raise SystemExit(f"ZIPA checkpoint is missing {missing[:5]}")
    model.eval()
    convert_scaled_to_non_scaled(model, inplace=True, is_onnx=False)
    zipformer.SimpleDownsample.forward = downsample
    wrap = Masked(model).eval()

    torch.manual_seed(0)
    example = (torch.randn(1, ZIPA_WINDOW, 80) * 3 - 8, torch.tensor([800], dtype=torch.int32))
    with torch.no_grad():
        traced = torch.jit.trace(wrap, example, check_trace=False, strict=False)
    package = convert(traced, [ct.TensorType(name="fbank", shape=(1, ZIPA_WINDOW, 80), dtype=np.float32),
                               ct.TensorType(name="length", shape=(1,), dtype=np.int32)])

    # tokens.txt: "<symbol> <id>" per line. Split on the last space: some symbols are combining marks.
    pairs = []
    for line in Path(hf_hub_download(ZIPA_REPO, "tokens.txt", revision=ZIPA_REVISION)).read_text("utf-8").split("\n"):
        symbol, _, index = line.rpartition(" ")
        if index.isdigit() and _:
            pairs.append((symbol, int(index)))
    tokens = [""] * (max(i for _, i in pairs) + 1)
    for symbol, i in pairs:
        tokens[i] = symbol
    return package, {"blank": 0, "tokens": tokens}


# ---------------------------------------------------------------- HuBERT / wav2vec2


class ManualLayerNorm(nn.Module):
    """The feature encoder's LayerNorms, written out: the fused op aborts MPSGraph on the GPU."""

    def __init__(self, ln):
        super().__init__()
        self.weight, self.bias, self.eps = ln.weight, ln.bias, ln.eps

    def forward(self, x):
        mu = x.mean(-1, keepdim=True)
        var = ((x - mu) ** 2).mean(-1, keepdim=True)
        return (x - mu) * torch.rsqrt(var + self.eps) * self.weight + self.bias


def w2v_package(model_id: str):
    """Exact-length export (1-30 s) with 8-bit per-channel symmetric weights. Never pad these inputs."""
    from huggingface_hub import hf_hub_download
    from transformers import AutoModelForCTC

    repo, revision = W2V[model_id]
    hidden_layer = {"hubert8": 8, "xlsr8": 16}[model_id]
    model = AutoModelForCTC.from_pretrained(repo, revision=revision).eval()
    for conv in model.base_model.feature_extractor.conv_layers:
        if isinstance(getattr(conv, "layer_norm", None), nn.LayerNorm):
            conv.layer_norm = ManualLayerNorm(conv.layer_norm)

    class Wrap(nn.Module):
        def __init__(self):
            super().__init__()
            self.m = model

        def forward(self, audio):
            out = self.m(audio, output_hidden_states=True)
            return out.logits, out.hidden_states[hidden_layer]

    with torch.no_grad():
        traced = torch.jit.trace(Wrap().eval(), torch.randn(1, 64000), check_trace=False, strict=False)
    shape = ct.Shape((1, ct.RangeDim(16000, 480000, default=64000)))
    package = convert(traced, [ct.TensorType(name="audio", shape=shape, dtype=np.float32)])
    import coremltools.optimize.coreml as cto

    package = cto.linear_quantize_weights(package, cto.OptimizationConfig(global_config=cto.OpLinearQuantizerConfig(
        mode="linear_symmetric", dtype="int8", granularity="per_channel")))

    config = json.loads(Path(hf_hub_download(repo, "config.json", revision=revision)).read_text())
    vocab = json.loads(Path(hf_hub_download(repo, "vocab.json", revision=revision)).read_text("utf-8"))
    tokens = [""] * config["vocab_size"]
    for token, i in vocab.items():
        if i < len(tokens):
            tokens[i] = token
    return package, {"blank": config["pad_token_id"], "tokens": tokens}


# ---------------------------------------------------------------- main


def size_bytes(path: Path) -> int:
    if path.is_file():
        return path.stat().st_size
    return sum(p.stat().st_size for p in path.rglob("*") if p.is_file())


def main() -> None:
    engine, out, zipa_src = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
    if engine not in ENGINE_MODELS:
        raise SystemExit(f"unknown engine {engine}")
    out.mkdir(parents=True, exist_ok=True)
    models = []
    for model_id in ENGINE_MODELS[engine]:
        print(f"Converting {model_id}…", flush=True)
        package, vocab = zipa_package(zipa_src) if model_id == "zipa" else w2v_package(model_id)
        package_path, vocab_path = out / f"{model_id}.mlpackage", out / f"{model_id}-vocab.json"
        if package_path.exists():
            shutil.rmtree(package_path)
        package.save(str(package_path))
        vocab_path.write_text(json.dumps(vocab, ensure_ascii=False))
        repo, revision = (ZIPA_REPO, ZIPA_REVISION) if model_id == "zipa" else W2V[model_id]
        entry = {"id": model_id, "package": package_path.name, "vocabulary": vocab_path.name,
                 "sizeBytes": size_bytes(package_path) + size_bytes(vocab_path),
                 "source": f"https://huggingface.co/{repo}", "revision": revision,
                 "licence": LICENCES[model_id]}
        if engine in RESTRICTED_SUBSTITUTIONS:
            table = json.loads((SUBSTITUTIONS_DIR / f"{model_id}.json").read_text("utf-8"))
            if table["vocab"] != vocab["tokens"]:
                raise SystemExit(f"{model_id}: the substitution table was made for another vocabulary")
            table_path = out / f"{model_id}-substitutions.json"
            table_path.write_text(json.dumps(table, ensure_ascii=False))
            entry["substitutions"] = table_path.name
            entry["sizeBytes"] += size_bytes(table_path)
        models.append(entry)
    manifest = {"engineID": engine, "engineVersion": ENGINE_VERSION, "models": models,
                "sizeBytes": sum(m["sizeBytes"] for m in models)}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2))
    print(f"{engine}: {manifest['sizeBytes'] / 1e6:.0f} MB", flush=True)


if __name__ == "__main__":
    os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
    main()
