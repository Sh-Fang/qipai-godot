"""JSON-lines TCP server: the Godot client sends one request per line.

Request:  {"id": 1, "cmd": "new_game" | "state" | "step" | "bid" | "double" | "play" | "pass" | "hint", ...}
Response: {"id": 1, "ok": true, "event": {...} | null, "state": {...}, "hint": [...]}
          {"id": 1, "ok": false, "error": "管不上", "state": {...}}
"""
import argparse
import json
import socket

from .ai import DouZeroPolicy
from .session import GameSession, RuleError

DEFAULT_PORT = 47321


def handle(session: GameSession, req: dict) -> dict:
    cmd = req.get("cmd")
    resp = {"id": req.get("id"), "ok": True, "event": None}
    try:
        if cmd == "new_game":
            session.new_game()
        elif cmd == "state":
            pass
        elif cmd == "step":
            resp["event"] = session.step()
        elif cmd == "bid":
            resp["event"] = session.human_bid(bool(req.get("call")))
        elif cmd == "double":
            resp["event"] = session.human_double(bool(req.get("double")))
        elif cmd == "play":
            resp["event"] = session.human_play([int(c) for c in req.get("cards", [])])
        elif cmd == "pass":
            resp["event"] = session.human_pass()
        elif cmd == "hint":
            resp["hint"] = session.hint(int(req.get("index", 0)))
        else:
            raise RuleError(f"unknown cmd {cmd!r}")
    except RuleError as e:
        resp.update(ok=False, error=str(e))
    resp["state"] = session.state()
    return resp


def serve(port: int, once: bool = False):
    policy = DouZeroPolicy()
    session = GameSession(policy)
    with socket.create_server(("127.0.0.1", port), reuse_port=False) as srv:
        print(f"douzero-core listening on 127.0.0.1:{port}", flush=True)
        while True:
            conn, _ = srv.accept()
            with conn, conn.makefile("rwb") as f:
                for line in f:
                    if not line.strip():
                        continue
                    try:
                        resp = handle(session, json.loads(line))
                    except Exception as e:  # keep serving even on bugs
                        resp = {"ok": False, "error": f"core error: {e!r}", "state": session.state()}
                    f.write(json.dumps(resp, ensure_ascii=False).encode() + b"\n")
                    f.flush()
            if once:
                return


def main():
    ap = argparse.ArgumentParser(description="DouZero algorithm core server")
    ap.add_argument("--port", type=int, default=DEFAULT_PORT)
    ap.add_argument("--once", action="store_true",
                    help="exit after the first client disconnects (used when Godot spawns the core)")
    args = ap.parse_args()
    serve(args.port, args.once)
