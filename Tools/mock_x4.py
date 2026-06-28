#!/usr/bin/env python3
"""Mock X4 remote-reader WebSocket server — stands in for the device so the phone
client can be validated without hardware. Speaks the live protocol subset:

  on connect            -> {"evt":"ready"}
  {"cmd":"ping"}        -> {"evt":"pong"}
  {"cmd":"goto",s,p}    -> {"evt":"goto","spine":s,"para":p,"ok":true}   (logged)

Usage: mock_x4.py [port]   (default 8181). Logs every received command to stdout.
"""
import asyncio
import json
import sys

import websockets

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8181


async def handle(ws):
    print("CONNECT", flush=True)
    await ws.send(json.dumps({"evt": "ready"}))
    async for raw in ws:
        print(f"RECV {raw}", flush=True)
        try:
            msg = json.loads(raw)
        except json.JSONDecodeError:
            continue
        cmd = msg.get("cmd")
        if cmd == "ping":
            await ws.send(json.dumps({"evt": "pong"}))
        elif cmd == "goto":
            await ws.send(json.dumps({
                "evt": "goto", "spine": msg.get("spine"), "para": msg.get("para"), "ok": True
            }))


async def main():
    print(f"mock X4 listening on ws://localhost:{PORT}", flush=True)
    async with websockets.serve(handle, "localhost", PORT):
        await asyncio.Future()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
