from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from app.database import get_db
from app.services.game_coordinator import coordinator
from bson import ObjectId
import json
import datetime

router = APIRouter(tags=["websockets"])

@router.websocket("/ws")
async def websocket_endpoint(
    websocket: WebSocket,
    token: str = Query(...),
    contestId: str = Query(...)
):
    await websocket.accept()
    
    db = get_db()
    
    # 1. Validate deviceToken
    user = await db.users.find_one({"deviceToken": token})
    if not user:
        await websocket.close(code=4001, reason="Invalid device token")
        return

    # 2. Validate contestId
    if not ObjectId.is_valid(contestId):
        await websocket.close(code=4002, reason="Invalid contest ID")
        return

    contest = await db.contests.find_one({"_id": ObjectId(contestId)})
    if not contest:
        await websocket.close(code=4003, reason="Contest not found")
        return

    # 3. Check if user is enlisted contender
    if user["_id"] not in contest.get("contenders", []):
        await websocket.close(code=4004, reason="User is not enlisted in this contest")
        return

    # Store user_id in scope for coordinator personalized broadcasts
    websocket.scope["user_id"] = str(user["_id"])

    # Register connection in game coordinator
    await coordinator.register_connection(contestId, websocket)

    try:
        while True:
            data = await websocket.receive_text()
            try:
                msg = json.loads(data)
                event = msg.get("event")
                payload = msg.get("data", {})
                
                if event == "SUBMIT_ANSWER":
                    question_id = payload.get("questionId")
                    selected_idx = payload.get("selectedOptionIndex")
                    time_taken = payload.get("timeTakenMs")
                    
                    if question_id is not None and selected_idx is not None and time_taken is not None:
                        try:
                            res = await process_websocket_submission(
                                contestId=contestId,
                                userId=user["_id"],
                                questionId=question_id,
                                selectedOptionIndex=selected_idx,
                                timeTakenMs=time_taken,
                                db=db
                            )
                            await websocket.send_json({
                                "event": "ANSWER_RESULT",
                                "data": {
                                    "isCorrect": res["isCorrect"],
                                    "score": res["score"]
                                }
                            })
                        except Exception as e:
                            await websocket.send_json({
                                "event": "SUBMIT_ERROR",
                                "data": {"detail": str(e)}
                            })
            except json.JSONDecodeError:
                pass
    except WebSocketDisconnect:
        pass
    finally:
        await coordinator.unregister_connection(contestId, websocket)

async def process_websocket_submission(
    contestId: str,
    userId: ObjectId,
    questionId: str,
    selectedOptionIndex: int,
    timeTakenMs: int,
    db
) -> dict:
    contest = await db.contests.find_one({"_id": ObjectId(contestId)})
    if not contest:
        raise Exception("Contest not found")
    if contest["status"] != "ACTIVE":
        raise Exception("Contest is not active")

    # Double submit check
    already_submitted = await db.submissions.find_one({
        "contestId": ObjectId(contestId),
        "userId": userId,
        "questionId": ObjectId(questionId)
    })
    if already_submitted:
        raise Exception("Answer already submitted for this question")

    # Questionnaire
    questionnaire = await db.questionnaires.find_one({"title": contest["questionnaireTitle"]})
    if not questionnaire:
        raise Exception("Questionnaire not found")

    question = next((q for q in questionnaire["questions"] if str(q["_id"]) == questionId), None)
    if not question:
        raise Exception("Question not found in questionnaire")

    shuffle = next((s for s in contest.get("questionShuffles", []) if str(s["questionId"]) == questionId), None)
    if not shuffle:
        raise Exception("Option shuffle map not found for question")

    if selectedOptionIndex < 0 or selectedOptionIndex >= len(shuffle["shuffledOptions"]):
        raise Exception("Invalid option index")

    selected_text = shuffle["shuffledOptions"][selectedOptionIndex]
    correct_text = question["options"][0]
    is_correct = (selected_text == correct_text)

    score = 0.0
    if is_correct:
        time_limit = question["timeLimitSeconds"]
        time_taken = max(0, min(timeTakenMs, time_limit * 1000))
        score = question["initialScore"] * (1.0 - (time_taken / (time_limit * 1000.0)))
        score = round(score, 2)

    doc = {
        "contestId": ObjectId(contestId),
        "userId": userId,
        "questionId": ObjectId(questionId),
        "selectedOptionIndex": selectedOptionIndex,
        "isCorrect": is_correct,
        "timeTakenMs": timeTakenMs,
        "score": score,
        "submittedAt": datetime.datetime.utcnow()
    }
    await db.submissions.insert_one(doc)
    return {"isCorrect": is_correct, "score": score}
