import json
import os
from typing import Any
from uuid import uuid4

import uvicorn
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect, status

app = FastAPI(title="Live Safety Demo API")

active_sessions: set[str] = set()
session_sockets: dict[str, WebSocket] = {}


@app.get("/health")
async def health() -> dict[str, bool]:
    return {"ready": True}


@app.post("/sessions", status_code=status.HTTP_201_CREATED)
async def create_session() -> dict[str, str]:
    session_id = str(uuid4())
    active_sessions.add(session_id)
    return {
        "session_id": session_id,
        "status": "active",
        "websocket_path": f"/ws/live/{session_id}",
    }


@app.delete("/sessions/{session_id}")
async def end_session(session_id: str) -> dict[str, str]:
    if session_id not in active_sessions:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Session not found")

    active_sessions.remove(session_id)
    websocket = session_sockets.pop(session_id, None)
    if websocket is not None:
        await websocket.close(code=1000, reason="Session ended")

    return {"session_id": session_id, "status": "ended"}


@app.websocket("/ws/live/{session_id}")
async def live_socket(websocket: WebSocket, session_id: str) -> None:
    if session_id not in active_sessions:
        await websocket.close(code=1008, reason="Session not found or ended")
        return

    await websocket.accept()
    session_sockets[session_id] = websocket
    await websocket.send_json({"type": "session_ready", "session_id": session_id})

    try:
        while True:
            message = await websocket.receive_text()
            try:
                event: Any = json.loads(message)
            except json.JSONDecodeError:
                await websocket.send_json({"type": "error", "message": "Expected a JSON message"})
                continue

            if not isinstance(event, dict):
                await websocket.send_json({"type": "error", "message": "Expected a JSON object"})
                continue

            event_type = event.get("type")
            if event_type == "ping":
                await websocket.send_json({"type": "pong"})
            elif event_type in {"video_frame", "audio_chunk"}:
                await websocket.send_json(
                    {
                        "type": "media_received",
                        "stream": event_type,
                        "timestamp": event.get("timestamp"),
                    }
                )
            else:
                await websocket.send_json(
                    {"type": "error", "message": "Unsupported event type"}
                )
    except WebSocketDisconnect:
        pass
    finally:
        if session_sockets.get(session_id) is websocket:
            session_sockets.pop(session_id, None)


def main() -> None:
    certfile = os.getenv("SSL_CERTFILE")
    keyfile = os.getenv("SSL_KEYFILE")
    if bool(certfile) != bool(keyfile):
        raise RuntimeError("Set both SSL_CERTFILE and SSL_KEYFILE to enable HTTPS/WSS.")

    uvicorn.run(
        "backend.main:app",
        host=os.getenv("HOST", "0.0.0.0"),
        port=int(os.getenv("PORT", "8443")),
        ssl_certfile=certfile,
        ssl_keyfile=keyfile,
    )
