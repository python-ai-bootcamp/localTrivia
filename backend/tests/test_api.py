import pytest
import pytest_asyncio
from httpx import AsyncClient
from app.main import app
from app.database import init_db, close_db, get_db
from app.config import ADMIN_USERNAME, ADMIN_PASSWORD
import time
from bson import ObjectId

@pytest_asyncio.fixture(autouse=True)
async def setup_test_db():
    # Force client initialization for test db
    import os
    os.environ["DATABASE_NAME"] = "local_trivia_test"
    await init_db()
    db = get_db()
    # Clean database before tests
    await db.users.delete_many({})
    await db.questionnaires.delete_many({})
    await db.contests.delete_many({})
    await db.submissions.delete_many({})
    yield
    # Clean database after tests
    await db.users.delete_many({})
    await db.questionnaires.delete_many({})
    await db.contests.delete_many({})
    await db.submissions.delete_many({})
    await close_db()

@pytest.mark.asyncio
async def test_root_endpoint():
    async with AsyncClient(app=app, base_url="http://test") as ac:
        response = await ac.get("/")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"

@pytest.mark.asyncio
async def test_user_registration():
    async with AsyncClient(app=app, base_url="http://test") as ac:
        # Register user
        payload = {"deviceToken": "token-12345", "username": "trivia_master"}
        res = await ac.post("/register", json=payload)
        assert res.status_code == 201
        assert res.json()["username"] == "trivia_master"

        # Register duplicate username -> expect 409 Conflict
        payload2 = {"deviceToken": "token-67890", "username": "trivia_master"}
        res2 = await ac.post("/register", json=payload2)
        assert res2.status_code == 409

        # Register identical deviceToken -> expect 201 (idempotency, returns existing)
        res3 = await ac.post("/register", json=payload)
        assert res3.status_code == 201
        assert res3.json()["username"] == "trivia_master"

@pytest.mark.asyncio
async def test_questionnaire_crud_and_contest_creation():
    async with AsyncClient(app=app, base_url="http://test") as ac:
        auth = (ADMIN_USERNAME, ADMIN_PASSWORD)
        
        # 1. Create Questionnaire
        q_payload = {
            "title": "Science Vol. 1",
            "interQuestionBufferSeconds": 5,
            "questions": [
                {
                    "questionText": "What is the chemical symbol for Gold?",
                    "options": ["Au", "Ag", "Fe", "Cu"],
                    "timeLimitSeconds": 10,
                    "initialScore": 1000
                }
            ]
        }
        res = await ac.post("/admin/questionnaires", json=q_payload, auth=auth)
        assert res.status_code == 201
        q_id = res.json()["id"]
        assert q_id is not None

        # 2. Get Questionnaire
        res_get = await ac.get(f"/admin/questionnaires/{q_id}", auth=auth)
        assert res_get.status_code == 200
        assert res_get.json()["title"] == "Science Vol. 1"

        # 3. Create Contest with unique QR URL
        c_payload = {
            "questionnaire_title": "Science Vol. 1",
            "scheduledStartTime": int(time.time()) + 300,
            "entryFee": 5,
            "qr": "https://trivia.local/join?contestId=someContestUnique"
        }
        res_c = await ac.post("/admin/contests", json=c_payload, auth=auth)
        assert res_c.status_code == 201
        c_id = res_c.json()["id"]

        # Verify QR image data is generated
        res_c_get = await ac.get(f"/admin/contests/{c_id}", auth=auth)
        assert res_c_get.status_code == 200
        assert res_c_get.json()["qrCodeBase64"].startswith("data:image/png;base64,")

        # 4. Create Contest WITHOUT QR URL (should auto-generate)
        c_payload_no_qr = {
            "questionnaire_title": "Science Vol. 1",
            "scheduledStartTime": int(time.time()) + 300,
            "entryFee": 5
        }
        res_c_no_qr = await ac.post("/admin/contests", json=c_payload_no_qr, auth=auth)
        assert res_c_no_qr.status_code == 201
        c_id_no_qr = res_c_no_qr.json()["id"]

        # Verify QR URL and image data are automatically generated
        res_c_no_qr_get = await ac.get(f"/admin/contests/{c_id_no_qr}", auth=auth)
        assert res_c_no_qr_get.status_code == 200
        assert res_c_no_qr_get.json()["qr"] == f"http://127.0.0.1:8080/join?contestId={c_id_no_qr}"
        assert res_c_no_qr_get.json()["qrCodeBase64"].startswith("data:image/png;base64,")

        # 5. Fetch contest QR as JPEG image via Admin API (Basic Auth)
        res_qr = await ac.get(f"/admin/contests/{c_id_no_qr}/qr", auth=auth)
        assert res_qr.status_code == 200
        assert "image/jpeg" in res_qr.headers["content-type"]
        assert res_qr.content.startswith(b"\xff\xd8")

@pytest.mark.asyncio
async def test_participant_discover_and_enlist():
    async with AsyncClient(app=app, base_url="http://test") as ac:
        auth = (ADMIN_USERNAME, ADMIN_PASSWORD)
        
        # 1. Setup questionnaire & contest
        await ac.post("/admin/questionnaires", json={
            "title": "History Vol. 1",
            "questions": [
                {
                    "questionText": "Who was the first president of USA?",
                    "options": ["George Washington", "Thomas Jefferson", "John Adams", "Benjamin Franklin"],
                    "timeLimitSeconds": 15,
                    "initialScore": 1000
                }
            ]
        }, auth=auth)

        qr_url = "https://trivia.local/join?contestId=history101"
        res_c = await ac.post("/admin/contests", json={
            "questionnaire_title": "History Vol. 1",
            "scheduledStartTime": int(time.time()) + 10,
            "entryFee": 10,
            "qr": qr_url
        }, auth=auth)
        c_id = res_c.json()["id"]

        # 2. Register participant
        token = "test-participant-token"
        await ac.post("/register", json={"deviceToken": token, "username": "history_buff"})

        headers = {"Authorization": f"Bearer {token}"}

        # 3. Discover contest via QR URL
        res_add = await ac.post("/contests/add", json={"qr": qr_url}, headers=headers)
        assert res_add.status_code == 200
        assert res_add.json()["contestId"] == c_id

        # 4. Enlist in contest
        res_enlist = await ac.post(f"/contests/{c_id}/enlist", headers=headers)
        assert res_enlist.status_code == 200
        assert res_enlist.json()["prizePool"] == 10.0
