from motor.motor_asyncio import AsyncIOMotorClient
from app.config import MONGO_URI, DATABASE_NAME

client = None
db = None

def get_db():
    return db

async def init_db():
    global client, db
    client = AsyncIOMotorClient(MONGO_URI)
    db = client[DATABASE_NAME]
    
    # Create Indexes
    # Users indexes
    await db.users.create_index("deviceToken", unique=True)
    await db.users.create_index("username", unique=True)
    
    # Questionnaires indexes
    await db.questionnaires.create_index("title", unique=True)
    
    # Contests indexes
    await db.contests.create_index("status")
    await db.contests.create_index("qr", unique=True)
    
    # Submissions compound indexes
    await db.submissions.create_index([("contestId", 1), ("userId", 1)])
    await db.submissions.create_index([("contestId", 1), ("questionId", 1)])

async def close_db():
    global client
    if client:
        client.close()
