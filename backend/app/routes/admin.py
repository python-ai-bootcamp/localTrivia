from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPBasic, HTTPBasicCredentials
import secrets
from app.config import ADMIN_USERNAME, ADMIN_PASSWORD
from app.database import get_db
from app.models import QuestionnaireCreate, ContestCreate, ContestStatus
from bson import ObjectId
from datetime import datetime
import qrcode
import io
import base64

router = APIRouter(prefix="/admin", tags=["admin"])
security = HTTPBasic()

def authenticate_admin(credentials: HTTPBasicCredentials = Depends(security)):
    current_username_bytes = credentials.username.encode("utf8")
    correct_username_bytes = ADMIN_USERNAME.encode("utf8")
    is_correct_username = secrets.compare_digest(current_username_bytes, correct_username_bytes)

    current_password_bytes = credentials.password.encode("utf8")
    correct_password_bytes = ADMIN_PASSWORD.encode("utf8")
    is_correct_password = secrets.compare_digest(current_password_bytes, correct_password_bytes)

    if not (is_correct_username and is_correct_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect admin username or password",
            headers={"WWW-Authenticate": "Basic"},
        )
    return credentials.username

# --- Questionnaire CRUD ---

@router.post("/questionnaires", status_code=status.HTTP_201_CREATED, dependencies=[Depends(authenticate_admin)])
async def create_questionnaire(payload: QuestionnaireCreate):
    db = get_db()
    
    # Check duplicate title
    exists = await db.questionnaires.find_one({"title": payload.title})
    if exists:
        raise HTTPException(status_code=409, detail="A questionnaire with this title already exists")

    questions_data = []
    for q in payload.questions:
        if len(q.options) != 4:
            raise HTTPException(status_code=400, detail="Each question must have exactly 4 options")
        
        questions_data.append({
            "_id": ObjectId(),
            "questionText": q.questionText,
            "options": q.options,
            "timeLimitSeconds": q.timeLimitSeconds,
            "initialScore": q.initialScore
        })

    doc = {
        "title": payload.title,
        "interQuestionBufferSeconds": payload.interQuestionBufferSeconds,
        "questions": questions_data,
        "createdAt": datetime.utcnow()
    }

    res = await db.questionnaires.insert_one(doc)
    return {"id": str(res.inserted_id)}

@router.get("/questionnaires", dependencies=[Depends(authenticate_admin)])
async def list_questionnaires():
    db = get_db()
    cursor = db.questionnaires.find()
    results = await cursor.to_list(length=100)
    for r in results:
        r["_id"] = str(r["_id"])
        for q in r.get("questions", []):
            q["_id"] = str(q["_id"])
    return results

@router.get("/questionnaires/{id}", dependencies=[Depends(authenticate_admin)])
async def get_questionnaire(id: str):
    db = get_db()
    if not ObjectId.is_valid(id):
        raise HTTPException(status_code=400, detail="Invalid questionnaire ID")

    doc = await db.questionnaires.find_one({"_id": ObjectId(id)})
    if not doc:
        raise HTTPException(status_code=404, detail="Questionnaire not found")

    doc["_id"] = str(doc["_id"])
    for q in doc.get("questions", []):
        q["_id"] = str(q["_id"])
    return doc

@router.put("/questionnaires/{id}", dependencies=[Depends(authenticate_admin)])
async def update_questionnaire(id: str, payload: QuestionnaireCreate):
    db = get_db()
    if not ObjectId.is_valid(id):
        raise HTTPException(status_code=400, detail="Invalid questionnaire ID")

    # Check duplicate title but exclude current ID
    exists = await db.questionnaires.find_one({"title": payload.title, "_id": {"$ne": ObjectId(id)}})
    if exists:
        raise HTTPException(status_code=409, detail="Another questionnaire with this title already exists")

    questions_data = []
    for q in payload.questions:
        if len(q.options) != 4:
            raise HTTPException(status_code=400, detail="Each question must have exactly 4 options")
        
        questions_data.append({
            "_id": ObjectId(),
            "questionText": q.questionText,
            "options": q.options,
            "timeLimitSeconds": q.timeLimitSeconds,
            "initialScore": q.initialScore
        })

    doc = {
        "title": payload.title,
        "interQuestionBufferSeconds": payload.interQuestionBufferSeconds,
        "questions": questions_data,
    }

    res = await db.questionnaires.update_one({"_id": ObjectId(id)}, {"$set": doc})
    if res.matched_count == 0:
        raise HTTPException(status_code=404, detail="Questionnaire not found")

    return {"message": "Questionnaire updated successfully"}

@router.delete("/questionnaires/{id}", dependencies=[Depends(authenticate_admin)])
async def delete_questionnaire(id: str):
    db = get_db()
    if not ObjectId.is_valid(id):
        raise HTTPException(status_code=400, detail="Invalid questionnaire ID")

    res = await db.questionnaires.delete_one({"_id": ObjectId(id)})
    if res.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Questionnaire not found")

    return {"message": "Questionnaire deleted successfully"}

# --- Contest Management ---

@router.post("/contests", status_code=status.HTTP_201_CREATED, dependencies=[Depends(authenticate_admin)])
async def create_contest(payload: ContestCreate):
    db = get_db()

    # Validate questionnaire title exists
    questionnaire = await db.questionnaires.find_one({"title": payload.questionnaire_title})
    if not questionnaire:
        raise HTTPException(status_code=400, detail="Linked questionnaire does not exist")

    # Validate unique QR url
    exists = await db.contests.find_one({"qr": payload.qr})
    if exists:
        raise HTTPException(status_code=409, detail="A contest with this QR code URL already exists")

    # Generate QR Code image (base64 PNG)
    try:
        qr_img = qrcode.make(payload.qr)
        buffered = io.BytesIO()
        qr_img.save(buffered, format="PNG")
        qr_base64 = "data:image/png;base64," + base64.b64encode(buffered.getvalue()).decode("utf-8")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to generate QR code image: {e}")

    doc = {
        "questionnaireTitle": payload.questionnaire_title,
        "scheduledStartTime": payload.scheduledStartTime,
        "status": ContestStatus.SCHEDULED,
        "contenders": [],
        "entryFee": payload.entryFee,
        "prizePool": 0.00,
        "qr": payload.qr,
        "qrCodeBase64": qr_base64,
        "currentQuestionIndex": -1,
        "questionShuffles": [],
        "finalLeaderboard": None,
        "createdAt": datetime.utcnow()
    }

    res = await db.contests.insert_one(doc)
    return {"id": str(res.inserted_id)}

@router.get("/contests", dependencies=[Depends(authenticate_admin)])
async def list_contests():
    db = get_db()
    cursor = db.contests.find()
    results = await cursor.to_list(length=100)
    for r in results:
        r["_id"] = str(r["_id"])
        r["contenders"] = [str(c) for c in r.get("contenders", [])]
        for s in r.get("questionShuffles", []):
            s["questionId"] = str(s["questionId"])
    return results

@router.get("/contests/{id}", dependencies=[Depends(authenticate_admin)])
async def get_contest(id: str):
    db = get_db()
    if not ObjectId.is_valid(id):
        raise HTTPException(status_code=400, detail="Invalid contest ID")

    doc = await db.contests.find_one({"_id": ObjectId(id)})
    if not doc:
        raise HTTPException(status_code=404, detail="Contest not found")

    doc["_id"] = str(doc["_id"])
    doc["contenders"] = [str(c) for c in doc.get("contenders", [])]
    for s in doc.get("questionShuffles", []):
        s["questionId"] = str(s["questionId"])
    return doc
