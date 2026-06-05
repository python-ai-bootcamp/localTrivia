from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.database import init_db, close_db
from app.services.game_coordinator import coordinator
from app.routes import admin, participant, ws
from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: Connect DB and start background game loops scheduler
    await init_db()
    await coordinator.start()
    yield
    # Shutdown: Close client connection
    await close_db()

app = FastAPI(
    title="Local Trivia App Backend",
    description="Synchronized real-time multiplayer trivia platform.",
    version="1.0.0",
    lifespan=lifespan
)

# Allow all origins for mobile/local dev testing
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Routers mounting
app.include_router(admin.router)
app.include_router(participant.router)
app.include_router(ws.router)

@app.get("/")
def read_root():
    return {"status": "ok", "service": "Local Trivia App Backend"}

@app.get("/status")
def read_status():
    return {"status": "up"}
