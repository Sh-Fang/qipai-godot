"""Convert Vincentzyx's 叫地主 model (bid_weights.pkl, Apache-2.0) to game/models/bid.onnx.

Source: https://github.com/Vincentzyx/DouZero_For_HLDDZ_FullAuto (BidModel.Net2).
Trained on DouZero self-play from sampled 17-card hands; the output is an
unbounded "bid score" (higher = better landlord hand). That project calls the
landlord above 0.2 and robs above 0.4.

Input x [N, 60]: the 17-card hand as a 4x15 matrix (columns 3..A, 2, 小王, 大王;
row r is 1 if the hand holds more than r of that rank), flattened row-major.
Output score [N, 1].

No torch needed: the checkpoint is read with a restricted unpickler that only
rebuilds float tensors, and the ONNX graph is written by hand.

    uv run python scripts/export_bid_model.py
"""
import collections
import io
import pickle
import tempfile
import urllib.request
import zipfile
from pathlib import Path

import numpy as np
import onnx
import onnxruntime as ort
from onnx import TensorProto, helper, numpy_helper

URL = "https://github.com/Vincentzyx/DouZero_For_HLDDZ_FullAuto/raw/main/weights/bid_weights.pkl"
OUT = Path(__file__).resolve().parents[2] / "game" / "models" / "bid.onnx"
RANK_COLUMN = {3: 0, 4: 1, 5: 2, 6: 3, 7: 4, 8: 5, 9: 6, 10: 7, 11: 8, 12: 9, 13: 10, 14: 11,
               17: 12, 20: 13, 30: 14}


def encode_hand(ranks) -> np.ndarray:
    """BidModel.EnvToOnehot, flattened."""
    m = np.zeros((4, 15), np.float32)
    for rank, n in collections.Counter(ranks).items():
        m[:n, RANK_COLUMN[rank]] = 1
    return m.reshape(-1)


def load_state_dict(data: bytes) -> dict[str, np.ndarray]:
    z = zipfile.ZipFile(io.BytesIO(data))
    prefix = z.namelist()[0].split("/")[0]

    class Unpickler(pickle.Unpickler):
        def find_class(self, module, name):
            if name == "_rebuild_tensor_v2":
                def rebuild(storage, offset, size, stride, *_):
                    return np.lib.stride_tricks.as_strided(
                        storage[offset:], shape=size, strides=[s * 4 for s in stride]).copy()
                return rebuild
            if name == "OrderedDict":
                return collections.OrderedDict
            if name == "FloatStorage":
                return name
            raise pickle.UnpicklingError(f"refusing {module}.{name}")

        def persistent_load(self, pid):
            _, storage_type, key, _, _ = pid
            assert storage_type == "FloatStorage"
            return np.frombuffer(z.read(f"{prefix}/data/{key}"), dtype=np.float32)

    return Unpickler(z.open(f"{prefix}/data.pkl")).load()


def reference_forward(sd, x: np.ndarray) -> float:
    """Net2.forward in numpy, for checking the exported graph."""
    lrelu = lambda v: np.where(v > 0, v, 0.01 * v)  # noqa: E731
    w, b = sd["conv1.weight"][:, 0, :], sd["conv1.bias"]
    xp = np.pad(x, (1, 1))
    conv = np.stack([np.correlate(xp, w[k], "valid") + b[k] for k in range(16)])
    h = np.concatenate([lrelu(conv).reshape(-1), x])
    for i in range(1, 5):
        h = lrelu(sd[f"dense{i}.weight"] @ h + sd[f"dense{i}.bias"])
    return float((sd["dense5.weight"] @ h + sd["dense5.bias"])[0])


def build_onnx(sd) -> onnx.ModelProto:
    inits = [numpy_helper.from_array(np.ascontiguousarray(v), k) for k, v in sd.items()]
    inits.append(numpy_helper.from_array(np.array([1], np.int64), "axis1"))
    nodes = [
        helper.make_node("Unsqueeze", ["x", "axis1"], ["x3"]),                       # [N,1,60]
        helper.make_node("Conv", ["x3", "conv1.weight", "conv1.bias"], ["c"], pads=[1, 1]),
        helper.make_node("LeakyRelu", ["c"], ["c_act"], alpha=0.01),                 # [N,16,60]
        helper.make_node("Flatten", ["c_act"], ["c_flat"], axis=1),                  # [N,960]
        helper.make_node("Concat", ["c_flat", "x"], ["h0"], axis=1),                 # [N,1020]
    ]
    for i in range(1, 6):
        out = "score" if i == 5 else f"g{i}"
        nodes.append(helper.make_node("Gemm", [f"h{i - 1}", f"dense{i}.weight", f"dense{i}.bias"],
                                      [out], transB=1))
        if i < 5:
            nodes.append(helper.make_node("LeakyRelu", [out], [f"h{i}"], alpha=0.01))
    graph = helper.make_graph(
        nodes, "bid_net2",
        [helper.make_tensor_value_info("x", TensorProto.FLOAT, ["N", 60])],
        [helper.make_tensor_value_info("score", TensorProto.FLOAT, ["N", 1])],
        inits)
    model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 17)])
    model.ir_version = 8
    onnx.checker.check_model(model)
    return model


def main():
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "bid_weights.pkl"
        urllib.request.urlretrieve(URL, path)
        sd = load_state_dict(path.read_bytes())
    model = build_onnx(sd)
    OUT.write_bytes(model.SerializeToString())

    sess = ort.InferenceSession(str(OUT), providers=["CPUExecutionProvider"])
    rng = np.random.default_rng(0)
    deck = [r for r in range(3, 15) for _ in range(4)] + [17] * 4 + [20, 30]
    worst = 0.0
    for _ in range(200):
        x = encode_hand(rng.choice(deck, 17, replace=False))
        got = sess.run(["score"], {"x": x[None]})[0][0, 0]
        worst = max(worst, abs(got - reference_forward(sd, x)))
    assert worst < 1e-4, worst
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes); max diff vs numpy forward {worst:.1e}")


if __name__ == "__main__":
    main()
