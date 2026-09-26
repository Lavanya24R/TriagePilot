from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from datetime import datetime, timezone
from typing import List

app = FastAPI(title="TriagePilot Backend")

connected_clients: List[WebSocket] = []

@app.get("/")
async def root():
    return {
        "service": "TriagePilot Backend",
        "status": "online"
    }

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()

    connected_clients.append(websocket)

    print("Responder connected.")
    print(f"Connected responders: {len(connected_clients)}")

    try:
        while True:
            # Keep connection alive
            await websocket.receive_text()

    except WebSocketDisconnect:
        if websocket in connected_clients:
            connected_clients.remove(websocket)

        print("Responder disconnected.")
        print(f"Connected responders: {len(connected_clients)}")

@app.post("/alert")
async def receive_alert(alert: dict):

    incident = {
        "id": f"INC-{int(datetime.now().timestamp())}",
        "type": alert.get("type", "manual_sos"),
        "severity": alert.get("severity", "high"),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "message": alert.get(
            "message",
            "Emergency SOS triggered"
        )
    }

    print("\n🚨 EMERGENCY ALERT")
    print(incident)

    disconnected_clients = []

    for client in connected_clients:

        try:
            await client.send_json(incident)

        except Exception:
            disconnected_clients.append(client)

    for client in disconnected_clients:
        if client in connected_clients:
            connected_clients.remove(client)

    return {
        "success": True,
        "incident": incident
    }