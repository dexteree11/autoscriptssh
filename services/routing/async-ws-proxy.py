# File: /opt/imagitech/services/routing/async-ws-proxy.py
# Purpose: High-performance Asynchronous WebSocket to SSH multiplexer.

import asyncio
import logging
import sys

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# Backend configuration (Dropbear native port)
BACKEND_HOST = '127.0.0.1'
BACKEND_PORT = 109

async def forward_stream(src_reader, dst_writer, direction):
    """Asynchronously forwards bytes from one stream to another."""
    try:
        while True:
            data = await src_reader.read(8192)
            if not data:
                break
            dst_writer.write(data)
            await dst_writer.drain()
    except ConnectionResetError:
        pass  # Normal disconnect
    except Exception as e:
        logging.debug(f"Stream error ({direction}): {e}")
    finally:
        if not dst_writer.is_closing():
            dst_writer.close()
            await dst_writer.wait_closed()

async def handle_client(reader, writer):
    """Handles incoming client handshakes and establishes the bi-directional tunnel."""
    peer = writer.get_extra_info('peername')
    
    try:
        # Read the initial payload with a strict timeout to prevent slow-loris attacks
        data = await asyncio.wait_for(reader.read(8192), timeout=5.0)
        if not data:
            writer.close()
            await writer.wait_closed()
            return

        req_str = data.decode('utf-8', errors='ignore')
        
        # HTTP Injector / ISP Bypass spoofing
        if "HTTP/" in req_str or "Upgrade:" in req_str or "upgrade:" in req_str:
            response = b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"
            writer.write(response)
            await writer.drain()

        # Connect to the local Dropbear backend
        backend_reader, backend_writer = await asyncio.open_connection(BACKEND_HOST, BACKEND_PORT)
        
        # If it was a raw SSH connection, forward the initial bytes
        if "HTTP/" not in req_str:
            backend_writer.write(data)
            await backend_writer.drain()

        # Run both forwarding streams concurrently
        await asyncio.gather(
            forward_stream(reader, backend_writer, "Client -> Backend"),
            forward_stream(backend_reader, writer, "Backend -> Client")
        )

    except asyncio.TimeoutError:
        logging.warning(f"Timeout reading initial payload from {peer}")
    except Exception as e:
        logging.error(f"Handler exception for {peer}: {e}")
    finally:
        if not writer.is_closing():
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass

async def main():
    # Bind to standard WS port and the custom payload port
    server_80 = await asyncio.start_server(handle_client, '0.0.0.0', 80)
    server_8880 = await asyncio.start_server(handle_client, '0.0.0.0', 8880)
    
    logging.info("Async WS Multiplexer started on ports 80 and 8880")
    
    async with server_80, server_8880:
        await asyncio.gather(
            server_80.serve_forever(),
            server_8880.serve_forever()
        )

if __name__ == '__main__':
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logging.info("Shutting down proxy.")

