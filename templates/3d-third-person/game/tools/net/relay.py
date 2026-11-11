"""A TCP relay with a delay each way and a byte counter, for a real round trip on one machine.

The browser's own network throttling does not touch WebSockets, and a localhost round trip is a
millisecond, so a probe that needs a bad network puts this between the client and the server: every
chunk is held back `--delay-ms` in each direction and let through in order (TCP never reorders), and
the bytes are counted both ways (WebSocket framing included, TCP/IP headers not). With
`--jitter-ms 30` each chunk waits up to that much more (still in order: the arrival
jitters as on a real network, which the game server's hold of four steps absorbs). With
`--stall-chance 0.02 --stall-ms 300` a chunk now and then costs a retransmission's wait, and
everything behind it waits too: what loss is on TCP. `--seed` makes the stalls repeat: each way has its
own generator, so the same chunks of a way stall in every run.

    python tools/net/relay.py --target 127.0.0.1:8910 --delay-ms 100 [--listen 0] [--stall-chance 0.02]

It prints `RELAY <port>` once it listens, and the byte counts every `--report-s` seconds and when it
stops. A probe can also import it and run `Relay` in a thread (`tools/web_smoke/net_link_smoke.py`).
"""

from __future__ import annotations

import argparse
import asyncio
import random
import threading
import time


class Relay:
    """Listens on a port and joins each connection to the target, with a delay each way."""

    def __init__(
        self,
        target_host: str,
        target_port: int,
        delay_s: float,
        listen_port: int = 0,
        stall_chance: float = 0.0,
        stall_s: float = 0.3,
        seed: int = 1,
        jitter_s: float = 0.0,
    ) -> None:
        self.target_host = target_host
        self.target_port = target_port
        self.delay_s = delay_s
        self.listen_port = listen_port
        self.stall_chance = stall_chance
        self.stall_s = stall_s
        self.jitter_s = jitter_s
        self.stalls = 0
        self.stalls_up = 0
        self.stalls_down = 0
        # When each stall came (seconds since the relay started) and its way: a failed gate prints them.
        self.stall_log: list[tuple[float, str]] = []
        self.began = time.perf_counter()
        # One generator a way, so the n-th chunk of a way stalls and jitters the same in every run whatever came the
        # other way between (one shared generator split the runner's 35 stalls anywhere from 20 to 29 up).
        self._rngs = {True: random.Random(seed), False: random.Random(seed + 1)}
        self.bytes_up = 0
        self.bytes_down = 0
        self.connections = 0
        # Bytes each way of every connection, in the order they came: {"up": n, "down": n}.
        self.per_connection: list[dict[str, int]] = []
        self.port = 0
        # Until this `time.perf_counter()` nothing is read from the server (`hold_down`).
        self._hold_down_until = 0.0
        self._loop: asyncio.AbstractEventLoop | None = None
        self._server: asyncio.base_events.Server | None = None
        self._ready = threading.Event()

    async def _pipe(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
        up: bool,
        counts: dict[str, int] | None = None,
    ) -> None:
        queue: asyncio.Queue[tuple[float, bytes]] = asyncio.Queue()

        async def deliver() -> None:
            while True:
                due, chunk = await queue.get()
                if not chunk:
                    break
                wait = due - time.perf_counter()
                if wait > 0:
                    await asyncio.sleep(wait)
                writer.write(chunk)
                await writer.drain()
            writer.close()

        rng = self._rngs[up]
        task = asyncio.create_task(deliver())
        last_due = 0.0
        try:
            while True:
                while not up and time.perf_counter() < self._hold_down_until:
                    await asyncio.sleep(0.05)
                chunk = await reader.read(65536)
                if up:
                    self.bytes_up += len(chunk)
                else:
                    self.bytes_down += len(chunk)
                if counts is not None:
                    counts["up" if up else "down"] += len(chunk)
                due = time.perf_counter() + self.delay_s
                if chunk and self.jitter_s > 0.0:
                    due += rng.uniform(0.0, self.jitter_s)
                if chunk and self.stall_chance > 0.0 and rng.random() < self.stall_chance:
                    due += self.stall_s
                    self.stalls += 1
                    self.stall_log.append((round(time.perf_counter() - self.began, 3), "up" if up else "down"))
                    if up:
                        self.stalls_up += 1
                    else:
                        self.stalls_down += 1
                # In order: a stalled chunk holds every chunk behind it.
                last_due = max(due, last_due)
                await queue.put((last_due, chunk))
                if not chunk:
                    break
        except (ConnectionError, OSError):
            await queue.put((0.0, b""))
        await task

    async def _handle(self, client_reader: asyncio.StreamReader, client_writer: asyncio.StreamWriter) -> None:
        self.connections += 1
        counts = {"up": 0, "down": 0}
        self.per_connection.append(counts)
        try:
            server_reader, server_writer = await asyncio.open_connection(self.target_host, self.target_port)
        except OSError:
            client_writer.close()
            return
        await asyncio.gather(
            self._pipe(client_reader, server_writer, up=True, counts=counts),
            self._pipe(server_reader, client_writer, up=False, counts=counts),
            return_exceptions=True,
        )

    async def serve(self) -> None:
        """Listens until the loop stops."""
        self._loop = asyncio.get_running_loop()
        self._server = await asyncio.start_server(self._handle, "127.0.0.1", self.listen_port)
        self.port = self._server.sockets[0].getsockname()[1]
        self._ready.set()
        async with self._server:
            await self._server.serve_forever()

    def start_in_thread(self) -> int:
        """Runs the relay on a thread of its own and returns its port."""
        threading.Thread(target=lambda: asyncio.run(self._run_quietly()), daemon=True).start()
        self._ready.wait(10)
        return self.port

    async def _run_quietly(self) -> None:
        try:
            await self.serve()
        except asyncio.CancelledError:
            pass

    def hold_down(self, seconds: float) -> None:
        """Stops reading what the server sends for `seconds` (every connection): the clients' downlink stalls, the
        server's socket and then its buffer fill, while what the clients send still reaches it."""
        self._hold_down_until = time.perf_counter() + seconds

    def stop(self) -> None:
        """Stops a relay started with `start_in_thread`."""
        if self._loop is not None and self._server is not None:
            self._loop.call_soon_threadsafe(self._server.close)

    def counts(self) -> str:
        return (
            f"connections={self.connections} up={self.bytes_up} B down={self.bytes_down} B stalls={self.stalls}"
            f" (up {self.stalls_up}, down {self.stalls_down})"
        )


async def _main(args: argparse.Namespace) -> None:
    host, port = args.target.rsplit(":", 1)
    relay = Relay(
        host,
        int(port),
        args.delay_ms / 1000.0,
        args.listen,
        args.stall_chance,
        args.stall_ms / 1000.0,
        args.seed,
        args.jitter_ms / 1000.0,
    )
    serving = asyncio.create_task(relay.serve())
    while not relay.port:
        await asyncio.sleep(0.01)
    print(f"RELAY {relay.port}", flush=True)
    try:
        while True:
            await asyncio.sleep(args.report_s)
            print(f"COUNT {relay.counts()}", flush=True)
    finally:
        print(f"COUNT {relay.counts()}", flush=True)
        serving.cancel()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--target", required=True, help="host:port of the server")
    parser.add_argument("--delay-ms", type=float, default=100.0, help="delay each way")
    parser.add_argument("--listen", type=int, default=0, help="port to listen on (0: a free one)")
    parser.add_argument("--stall-chance", type=float, default=0.0, help="chance a chunk stalls")
    parser.add_argument("--stall-ms", type=float, default=300.0, help="what a stall costs")
    parser.add_argument("--seed", type=int, default=1, help="seed of the stalls and the jitter")
    parser.add_argument("--jitter-ms", type=float, default=0.0, help="up to this much more delay a chunk")
    parser.add_argument("--report-s", type=float, default=5.0, help="seconds between byte counts")
    try:
        asyncio.run(_main(parser.parse_args()))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
