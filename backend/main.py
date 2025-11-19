from fastapi import FastAPI, WebSocket
from fastapi.middleware.cors import CORSMiddleware
from routes import router
from websocket_handler import lobby_websocket_endpoint, game_websocket_endpoint
from database import Base, engine
import db_models  # Import to ensure GameModel is registered with Base

# Ensure database tables are created at startup
Base.metadata.create_all(bind=engine)

app = FastAPI(title="UNO Game Backend", version="1.0.0")

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*", "https://uno.jersweb.net", "http://uno.jersweb.net"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include API routes
app.include_router(router)

# WebSocket endpoints
@app.websocket("/ws/lobby/{player_id}")
async def lobby_ws(websocket: WebSocket, player_id: str):
    await lobby_websocket_endpoint(websocket, player_id)


@app.websocket("/ws/{game_id}/{player_id}")
async def game_ws(websocket: WebSocket, game_id: str, player_id: str):
    await game_websocket_endpoint(websocket, game_id, player_id)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
