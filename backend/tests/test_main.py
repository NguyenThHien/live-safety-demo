import unittest

from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from backend.main import app


class LiveSessionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.client = TestClient(app)

    def test_health(self) -> None:
        response = self.client.get("/health")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"ready": True})

    def test_session_lifecycle_and_live_messages(self) -> None:
        created = self.client.post("/sessions")
        self.assertEqual(created.status_code, 201)
        session = created.json()
        session_id = session["session_id"]

        with self.client.websocket_connect(session["websocket_path"]) as websocket:
            self.assertEqual(
                websocket.receive_json(),
                {"type": "session_ready", "session_id": session_id},
            )
            websocket.send_json({"type": "video_frame", "timestamp": 1234, "data": "frame"})
            self.assertEqual(
                websocket.receive_json(),
                {"type": "media_received", "stream": "video_frame", "timestamp": 1234},
            )
            websocket.send_json({"type": "audio_chunk", "timestamp": 1235, "data": "audio"})
            self.assertEqual(
                websocket.receive_json(),
                {"type": "media_received", "stream": "audio_chunk", "timestamp": 1235},
            )
            websocket.send_json({"type": "ping"})
            self.assertEqual(websocket.receive_json(), {"type": "pong"})

            ended = self.client.delete(f"/sessions/{session_id}")
            self.assertEqual(ended.status_code, 200)
            self.assertEqual(ended.json(), {"session_id": session_id, "status": "ended"})
            with self.assertRaises(WebSocketDisconnect):
                websocket.receive_json()

        with self.assertRaises(WebSocketDisconnect):
            with self.client.websocket_connect(session["websocket_path"]):
                pass

        missing = self.client.delete(f"/sessions/{session_id}")
        self.assertEqual(missing.status_code, 404)


if __name__ == "__main__":
    unittest.main()
