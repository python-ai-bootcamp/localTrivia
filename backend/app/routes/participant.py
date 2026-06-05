from fastapi import APIRouter, Header, Depends, HTTPException, status, Response
from fastapi.responses import HTMLResponse
from app.database import get_db
from app.models import UserRegisterRequest, SubmissionRequest, ContestStatus
from bson import ObjectId
from datetime import datetime
from typing import Optional
import time
import base64
import io
from PIL import Image

router = APIRouter(tags=["participants"])

async def get_current_user(authorization: str = Header(...)):
    if not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authorization header format"
        )
    token = authorization.split(" ")[1]
    db = get_db()
    user = await db.users.find_one({"deviceToken": token})
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or unregistered device token"
        )
    return user

# Helper to compute user-specific contest status
def get_user_contest_status(contest: dict, user_id_str: str) -> str:
    contenders = [str(c) for c in contest.get("contenders", [])]
    is_contender = user_id_str in contenders
    c_status = contest.get("status", ContestStatus.SCHEDULED)

    if c_status == ContestStatus.COMPLETED:
        return "COMPLETED"
    elif is_contender:
        if c_status == ContestStatus.ACTIVE:
            return "LIVE"
        else:
            return "ENLISTED"
    else:
        if c_status == ContestStatus.SCHEDULED:
            return "ADDED"
        else:
            return "MISSED"

# --- User Management ---

@router.post("/register", status_code=status.HTTP_201_CREATED)
async def register_user(payload: UserRegisterRequest):
    db = get_db()

    # Registration idempotency for device token
    exists_token = await db.users.find_one({"deviceToken": payload.deviceToken})
    if exists_token:
        # Return existing profile
        return {"id": str(exists_token["_id"]), "username": exists_token["username"]}

    # Check unique username
    exists_name = await db.users.find_one({"username": payload.username})
    if exists_name:
        raise HTTPException(status_code=409, detail="Username already taken")

    doc = {
        "deviceToken": payload.deviceToken,
        "username": payload.username,
        "avatarUrl": f"https://api.dicebear.com/7.x/bottts/svg?seed={payload.username}",
        "addedContests": [],
        "createdAt": datetime.utcnow()
    }

    res = await db.users.insert_one(doc)
    return {"id": str(res.inserted_id), "username": payload.username}

# --- Contest Discovery & Actions ---

@router.post("/contests/add")
async def add_contest(payload: dict, current_user: dict = Depends(get_current_user)):
    db = get_db()
    qr_url = payload.get("qr")
    if not qr_url:
        raise HTTPException(status_code=400, detail="Missing QR URL")

    # Match contest exactly by QR URL
    contest = await db.contests.find_one({"qr": qr_url})
    if not contest:
        raise HTTPException(status_code=404, detail="Contest not found")

    contest_id = contest["_id"]
    
    # Add contest to user's dashboard if not already added
    if contest_id not in current_user.get("addedContests", []):
        await db.users.update_one(
            {"_id": current_user["_id"]},
            {"$addToSet": {"addedContests": contest_id}}
        )

    return {
        "message": "Contest added to dashboard successfully",
        "contestId": str(contest_id)
    }

@router.get("/contests")
async def list_user_contests(current_user: dict = Depends(get_current_user)):
    db = get_db()
    added_ids = current_user.get("addedContests", [])
    if not added_ids:
        return []

    cursor = db.contests.find({"_id": {"$in": added_ids}})
    results = await cursor.to_list(length=100)

    user_id_str = str(current_user["_id"])
    serialized = []
    for r in results:
        serialized.append({
            "id": str(r["_id"]),
            "questionnaireTitle": r["questionnaireTitle"],
            "scheduledStartTime": r["scheduledStartTime"],
            "entryFee": r["entryFee"],
            "prizePool": r["prizePool"],
            "qr": r["qr"],
            "qrCodeBase64": r["qrCodeBase64"],
            "status": get_user_contest_status(r, user_id_str),
            "originalStatus": r["status"] # SCHEDULED, ACTIVE, COMPLETED
        })
    return serialized

@router.get("/contests/{id}")
async def get_user_contest_detail(id: str, current_user: dict = Depends(get_current_user)):
    db = get_db()
    if not ObjectId.is_valid(id):
        raise HTTPException(status_code=400, detail="Invalid contest ID")

    contest = await db.contests.find_one({"_id": ObjectId(id)})
    if not contest:
        raise HTTPException(status_code=404, detail="Contest not found")

    user_id_str = str(current_user["_id"])
    return {
        "id": str(contest["_id"]),
        "questionnaireTitle": contest["questionnaireTitle"],
        "scheduledStartTime": contest["scheduledStartTime"],
        "entryFee": contest["entryFee"],
        "prizePool": contest["prizePool"],
        "qr": contest["qr"],
        "qrCodeBase64": contest["qrCodeBase64"],
        "status": get_user_contest_status(contest, user_id_str),
        "originalStatus": contest["status"],
        "contendersCount": len(contest.get("contenders", [])),
        "finalLeaderboard": contest.get("finalLeaderboard")
    }

@router.post("/contests/{id}/enlist")
async def enlist_contest(id: str, current_user: dict = Depends(get_current_user)):
    db = get_db()
    if not ObjectId.is_valid(id):
        raise HTTPException(status_code=400, detail="Invalid contest ID")

    contest = await db.contests.find_one({"_id": ObjectId(id)})
    if not contest:
        raise HTTPException(status_code=404, detail="Contest not found")

    if contest["status"] != ContestStatus.SCHEDULED:
        raise HTTPException(status_code=400, detail="Cannot enlist in active or finished contest")

    user_id = current_user["_id"]
    
    # Register as contender and auto-add contest to dashboard
    await db.contests.update_one(
        {"_id": contest["_id"]},
        {"$addToSet": {"contenders": user_id}}
    )
    await db.users.update_one(
        {"_id": user_id},
        {"$addToSet": {"addedContests": contest["_id"]}}
    )

    # Recalculate Prize Pool
    updated_contest = await db.contests.find_one({"_id": contest["_id"]})
    contenders_count = len(updated_contest.get("contenders", []))
    new_pool = float(contest["entryFee"] * contenders_count)
    await db.contests.update_one(
        {"_id": contest["_id"]},
        {"$set": {"prizePool": new_pool}}
    )

    return {"message": "Successfully enlisted", "prizePool": new_pool}

# --- Submissions ---

@router.post("/contests/{contestId}/submit")
async def submit_answer(contestId: str, payload: SubmissionRequest, current_user: dict = Depends(get_current_user)):
    db = get_db()
    if not ObjectId.is_valid(contestId):
        raise HTTPException(status_code=400, detail="Invalid contest ID")

    contest = await db.contests.find_one({"_id": ObjectId(contestId)})
    if not contest:
        raise HTTPException(status_code=404, detail="Contest not found")

    if contest["status"] != ContestStatus.ACTIVE:
        raise HTTPException(status_code=400, detail="Contest is not active")

    # Verify user is enlisted contender
    if current_user["_id"] not in contest.get("contenders", []):
        raise HTTPException(status_code=403, detail="User is not enlisted as a contender")

    # Prevent double submissions
    already_submitted = await db.submissions.find_one({
        "contestId": ObjectId(contestId),
        "userId": current_user["_id"],
        "questionId": ObjectId(payload.questionId)
    })
    if already_submitted:
        raise HTTPException(status_code=409, detail="Answer already submitted for this question")

    # Find questionnaire and target question
    questionnaire = await db.questionnaires.find_one({"title": contest["questionnaireTitle"]})
    if not questionnaire:
        raise HTTPException(status_code=404, detail="Questionnaire not found")

    question = next((q for q in questionnaire["questions"] if str(q["_id"]) == payload.questionId), None)
    if not question:
        raise HTTPException(status_code=404, detail="Question not found in questionnaire")

    # Verify option selection maps to index 0 of options (correct answer)
    shuffle = next((s for s in contest.get("questionShuffles", []) if str(s["questionId"]) == payload.questionId), None)
    if not shuffle:
        raise HTTPException(status_code=500, detail="Option shuffle map not found for question")

    if payload.selectedOptionIndex < 0 or payload.selectedOptionIndex >= len(shuffle["shuffledOptions"]):
        raise HTTPException(status_code=400, detail="Invalid option index")

    selected_text = shuffle["shuffledOptions"][payload.selectedOptionIndex]
    correct_text = question["options"][0]
    is_correct = (selected_text == correct_text)

    correct_option_index = 0
    try:
        correct_option_index = shuffle["shuffledOptions"].index(correct_text)
    except ValueError:
        pass

    score = 0.0
    if is_correct:
        time_limit = question["timeLimitSeconds"]
        # Cap time taken in bounds
        time_taken = max(0, min(payload.timeTakenMs, time_limit * 1000))
        # scoring speed multiplier
        score = question["initialScore"] * (1.0 - (time_taken / (time_limit * 1000.0)))
        score = round(score, 2)

    doc = {
        "contestId": ObjectId(contestId),
        "userId": current_user["_id"],
        "questionId": ObjectId(payload.questionId),
        "selectedOptionIndex": payload.selectedOptionIndex,
        "isCorrect": is_correct,
        "timeTakenMs": payload.timeTakenMs,
        "score": score,
        "submittedAt": datetime.utcnow()
    }

    await db.submissions.insert_one(doc)
    return {
        "isCorrect": is_correct,
        "score": score,
        "correctOptionIndex": correct_option_index
    }

# --- Onboarding Landing Page ---

@router.get("/join", response_class=HTMLResponse)
async def get_join_landing_page(contestId: str):
    html_content = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>Join Trivia Contest</title>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
            body {{
                background-color: #121212;
                color: #ffffff;
                font-family: 'Inter', sans-serif;
                display: flex;
                align-items: center;
                justify-content: center;
                height: 100vh;
                margin: 0;
                padding: 20px;
                box-sizing: border-box;
            }}
            .container {{
                text-align: center;
                max-width: 400px;
                background: rgba(255, 255, 255, 0.05);
                padding: 40px;
                border-radius: 16px;
                box-shadow: 0 8px 32px 0 rgba(0, 0, 0, 0.3);
                border: 1px solid rgba(255, 255, 255, 0.1);
            }}
            h1 {{
                font-size: 28px;
                margin-bottom: 20px;
                color: #ab47bc;
            }}
            p {{
                font-size: 16px;
                color: #b0bec5;
                margin-bottom: 30px;
                line-height: 1.5;
            }}
            .btn {{
                background: linear-gradient(135deg, #7b1fa2, #ab47bc);
                color: white;
                border: none;
                padding: 16px 32px;
                font-size: 18px;
                font-weight: bold;
                border-radius: 8px;
                cursor: pointer;
                width: 100%;
                transition: transform 0.2s, box-shadow 0.2s;
            }}
            .btn:active {{
                transform: scale(0.98);
            }}
        </style>
    </head>
    <body>
        <div class="container">
            <h1>Local Trivia Onboarding</h1>
            <p>Tap below to save your contest code and redirect to install or open the Local Trivia App!</p>
            <button class="btn" id="joinBtn">Join Contest</button>
        </div>
        <script>
            const contestId = "{contestId}";
            document.getElementById("joinBtn").addEventListener("click", async () => {{
                try {{
                    await navigator.clipboard.writeText("TRIVIA:" + contestId);
                }} catch (err) {{
                    console.error("Clipboard write failed:", err);
                }}
                
                const ua = navigator.userAgent || navigator.vendor || window.opera;
                if (/android/i.test(ua)) {{
                    window.location.href = "https://play.google.com/store/apps/details?id=com.trivia.local";
                }} else if (/iPad|iPhone|iPod/.test(ua) && !window.MSStream) {{
                    window.location.href = "https://apps.apple.com/app/local-trivia/id123456789";
                }} else {{
                    alert("Please open this link on your mobile phone to scan/join.");
                }}
            }});
        </script>
    </body>
    </html>
    """
    return HTMLResponse(content=html_content)
