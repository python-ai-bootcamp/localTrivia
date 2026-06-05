import os

MONGO_URI = os.getenv("MONGO_URI", "mongodb://localhost:27017/local_trivia")
DATABASE_NAME = os.getenv("DATABASE_NAME", "local_trivia")

ADMIN_USERNAME = os.getenv("ADMIN_USERNAME", "admin")
ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD", "trivia_admin_secret_123")

BASE_URL = os.getenv("BASE_URL", "http://127.0.0.1:8080")

