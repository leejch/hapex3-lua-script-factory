#!/usr/bin/env python3
"""Small stdlib WebSocket relay for the legacy HOOZi web radar.

Run this on the machine that opens the old radar page. HApex3.0 Lua connects as a
producer to ws://127.0.0.1:2334/ws and sends legacy radar JSON text frames; the
old web radar connects to the same URL as a passive client and receives them.
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import hashlib
import signal
import struct
from dataclasses import dataclass

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


@dataclass(eq=False)
class Client:
    reader: asyncio.StreamReader
    writer: asyncio.StreamWriter
    peer: str
    path: str
    messages: int = 0
    closed: bool = False


clients: set[Client] = set()


def parse_headers(raw: bytes) -> tuple[str, dict[str, str]]:
    text = raw.decode("latin1")
    lines = text.split("\r\n")
    request_line = lines[0]
    headers: dict[str, str] = {}
    for line in lines[1:]:
        if not line or ":" not in line:
            continue
        key, value = line.split(":", 1)
        headers[key.strip().lower()] = value.strip()
    return request_line, headers


def ws_accept(key: str) -> str:
    digest = hashlib.sha1((key + GUID).encode("ascii")).digest()
    return base64.b64encode(digest).decode("ascii")


async def read_http_request(reader: asyncio.StreamReader) -> bytes:
    data = await reader.readuntil(b"\r\n\r\n")
    if len(data) > 16384:
        raise ValueError("HTTP header too large")
    return data


async def handshake(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, expected_path: str) -> str:
    raw = await read_http_request(reader)
    request_line, headers = parse_headers(raw)
    parts = request_line.split()
    if len(parts) < 3 or parts[0].upper() != "GET":
        raise ValueError("not a websocket GET request")

    path = parts[1].split("?", 1)[0]
    if path != expected_path:
        writer.write(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n")
        await writer.drain()
        raise ValueError(f"unexpected path {path!r}")

    key = headers.get("sec-websocket-key")
    upgrade = headers.get("upgrade", "").lower()
    if not key or upgrade != "websocket":
        raise ValueError("missing websocket upgrade headers")

    response = (
        "HTTP/1.1 101 Switching Protocols\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Accept: {ws_accept(key)}\r\n"
        "\r\n"
    )
    writer.write(response.encode("ascii"))
    await writer.drain()
    return path


async def read_exact(reader: asyncio.StreamReader, n: int) -> bytes:
    data = await reader.readexactly(n)
    return data


async def read_frame(reader: asyncio.StreamReader) -> tuple[int, bytes] | None:
    try:
        head = await read_exact(reader, 2)
    except asyncio.IncompleteReadError:
        return None

    b1, b2 = head
    opcode = b1 & 0x0F
    masked = (b2 & 0x80) != 0
    length = b2 & 0x7F
    if length == 126:
        length = struct.unpack("!H", await read_exact(reader, 2))[0]
    elif length == 127:
        length = struct.unpack("!Q", await read_exact(reader, 8))[0]

    mask = await read_exact(reader, 4) if masked else b""
    payload = await read_exact(reader, length) if length else b""
    if masked:
        payload = bytes(byte ^ mask[i % 4] for i, byte in enumerate(payload))
    return opcode, payload


def make_frame(opcode: int, payload: bytes = b"") -> bytes:
    first = 0x80 | (opcode & 0x0F)
    length = len(payload)
    if length < 126:
        header = bytes([first, length])
    elif length <= 0xFFFF:
        header = bytes([first, 126]) + struct.pack("!H", length)
    else:
        header = bytes([first, 127]) + struct.pack("!Q", length)
    return header + payload


async def send_text(client: Client, text: str) -> None:
    if client.closed:
        return
    client.writer.write(make_frame(0x1, text.encode("utf-8")))
    await client.writer.drain()


async def broadcast(sender: Client, text: str) -> None:
    stale: list[Client] = []
    for client in list(clients):
        if client is sender or client.closed:
            continue
        try:
            await send_text(client, text)
        except Exception:
            stale.append(client)
    for client in stale:
        client.closed = True
        clients.discard(client)


async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, path: str) -> None:
    peer_info = writer.get_extra_info("peername")
    peer = f"{peer_info[0]}:{peer_info[1]}" if peer_info else "unknown"
    client: Client | None = None
    try:
        accepted_path = await handshake(reader, writer, path)
        client = Client(reader=reader, writer=writer, peer=peer, path=accepted_path)
        clients.add(client)
        print(f"[open] {peer} clients={len(clients)}", flush=True)

        while True:
            frame = await read_frame(reader)
            if frame is None:
                break
            opcode, payload = frame
            if opcode == 0x8:
                writer.write(make_frame(0x8, payload))
                await writer.drain()
                break
            if opcode == 0x9:
                writer.write(make_frame(0xA, payload))
                await writer.drain()
                continue
            if opcode != 0x1:
                continue

            text = payload.decode("utf-8", errors="replace")
            client.messages += 1
            await broadcast(client, text)
    except Exception as exc:
        print(f"[drop] {peer} {exc}", flush=True)
    finally:
        if client is not None:
            client.closed = True
            clients.discard(client)
        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass
        print(f"[close] {peer} clients={len(clients)}", flush=True)


async def main() -> None:
    parser = argparse.ArgumentParser(description="Legacy HOOZi web radar WebSocket relay")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=2334)
    parser.add_argument("--path", default="/ws")
    args = parser.parse_args()

    server = await asyncio.start_server(lambda r, w: handle_client(r, w, args.path), args.host, args.port)
    sockets = ", ".join(str(sock.getsockname()) for sock in server.sockets or [])
    print(f"legacy web radar relay listening on {sockets}{args.path}", flush=True)

    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, stop.set)
        except NotImplementedError:
            pass

    async with server:
        await stop.wait()
        server.close()
        await server.wait_closed()
        for client in list(clients):
            client.closed = True
            client.writer.close()
        await asyncio.gather(
            *(client.writer.wait_closed() for client in list(clients)),
            return_exceptions=True,
        )


if __name__ == "__main__":
    asyncio.run(main())
