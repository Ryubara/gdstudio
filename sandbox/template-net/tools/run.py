"""Runs the template-net spike: a headless server, a counting TCP proxy, one client; prints bytes per second.

    uv run --with psutil python tools/run.py --godot <godot> --mode send_bytes --players 8 --moving 8

The proxy counts what crosses the socket (WebSocket framing included, TCP/IP headers not), like the
Deadnight comparison's proxy (kit docs engines/godot/multiplayer.md#measuring).
"""

import argparse
import asyncio
import subprocess
import time
from pathlib import Path

import psutil

PROJECT = Path(__file__).resolve().parent.parent
OUT = Path(__file__).resolve().parent.parent.parent.parent.parent.parent.parent / "scratch" / "gdstudio" / "godot-research-simple-networking-for-3d-third"


class Proxy:
    def __init__(self, listen_port: int, target_port: int) -> None:
        self.listen_port, self.target_port = listen_port, target_port
        self.up = 0
        self.down = 0
        self.up_chunks = 0
        self.down_chunks = 0

    async def start(self) -> None:
        self.server = await asyncio.start_server(self._handle, "127.0.0.1", self.listen_port)

    async def _handle(self, c_reader, c_writer) -> None:
        s_reader, s_writer = await asyncio.open_connection("127.0.0.1", self.target_port)
        await asyncio.gather(
            self._pump(c_reader, s_writer, True), self._pump(s_reader, c_writer, False), return_exceptions=True
        )

    async def _pump(self, reader, writer, upward: bool) -> None:
        try:
            while data := await reader.read(65536):
                if upward:
                    self.up += len(data)
                    self.up_chunks += 1
                else:
                    self.down += len(data)
                    self.down_chunks += 1
                writer.write(data)
                await writer.drain()
        except ConnectionError:
            pass
        writer.close()


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--godot", required=True)
    ap.add_argument("--mode", required=True)
    ap.add_argument("--players", type=int, default=8)
    ap.add_argument("--moving", type=int, default=8)
    ap.add_argument("--seconds", type=int, default=12)
    ap.add_argument("--port", type=int, default=8940)
    ap.add_argument("--verbose", action="store_true")
    a = ap.parse_args()
    base = [a.godot, "--headless", "--path", str(PROJECT), "--"]
    common = [f"--mode={a.mode}", f"--players={a.players}", f"--moving={a.moving}"]
    server = subprocess.Popen(
        [*base, "--server", f"--port={a.port}", f"--run-seconds={a.seconds + 8}", *common],
        stdout=open(OUT / "server.log", "w"),
        stderr=subprocess.STDOUT,
    )
    proxy = Proxy(a.port + 1, a.port)
    await proxy.start()
    await asyncio.sleep(3)
    client = subprocess.Popen(
        [*base, f"--url=ws://127.0.0.1:{a.port + 1}", f"--run-seconds={a.seconds + 3}", *common],
        stdout=open(OUT / "client.log", "w"),
        stderr=subprocess.STDOUT,
    )
    await asyncio.sleep(3)
    ps = psutil.Process(server.pid)
    kids = [ps, *ps.children(recursive=True)]
    cpu0 = sum(p.cpu_times().user + p.cpu_times().system for p in kids)
    up0, down0, t0 = proxy.up, proxy.down, time.perf_counter()
    await asyncio.sleep(a.seconds)
    dt = time.perf_counter() - t0
    cpu = sum(p.cpu_times().user + p.cpu_times().system for p in kids) - cpu0
    up, down = proxy.up - up0, proxy.down - down0
    print(
        f"mode={a.mode} players={a.players} moving={a.moving}: down {down / dt / 1000:.2f} KB/s "
        f"({down / dt / 20:.0f} B per 20 Hz tick), up {up / dt / 1000:.2f} KB/s, server cpu {cpu / dt * 100:.1f}%"
    )
    for proc in (client, server):
        proc.terminate()
    for proc in (client, server):
        proc.wait(timeout=20)
    for name in ("server", "client"):
        text = (OUT / f"{name}.log").read_text(errors="replace")
        errors = [line for line in text.splitlines() if "ERROR" in line or "WARNING" in line]
        if errors or a.verbose:
            print("  ", name, errors[:3], text[-200:] if a.verbose else "")


asyncio.run(main())
