import asyncio
import time
from datetime import datetime
from bson import ObjectId
from typing import Dict, Set, List
import random
from fastapi import WebSocket
from app.database import get_db
from app.models import ContestStatus, QuestionShuffle, LeaderboardEntry

class GameCoordinator:
    def __init__(self):
        self.rooms: Dict[str, Set[WebSocket]] = {}
        self.running_tasks: Dict[str, asyncio.Task] = {}
        self.loop_started = False

    async def start(self):
        if not self.loop_started:
            self.loop_started = True
            asyncio.create_task(self.scheduler_loop())

    async def register_connection(self, contest_id: str, websocket: WebSocket):
        if contest_id not in self.rooms:
            self.rooms[contest_id] = set()
        self.rooms[contest_id].add(websocket)
        
        # Catch up connected player immediately if contest is live
        db = get_db()
        contest = await db.contests.find_one({"_id": ObjectId(contest_id)})
        if contest and contest["status"] == ContestStatus.ACTIVE:
            await self.send_catch_up(contest_id, websocket, contest)

    async def unregister_connection(self, contest_id: str, websocket: WebSocket):
        if contest_id in self.rooms:
            self.rooms[contest_id].discard(websocket)
            if not self.rooms[contest_id]:
                del self.rooms[contest_id]

    async def broadcast(self, contest_id: str, message: dict):
        if contest_id in self.rooms:
            for ws in list(self.rooms[contest_id]):
                try:
                    await ws.send_json(message)
                except Exception:
                    pass

    async def send_catch_up(self, contest_id: str, websocket: WebSocket, contest: dict):
        db = get_db()
        questionnaire = await db.questionnaires.find_one({"title": contest["questionnaireTitle"]})
        if not questionnaire:
            return

        now = time.time()
        start_time = contest["scheduledStartTime"]
        elapsed = now - start_time
        if elapsed < 0:
            return  # Contest hasn't started yet, client shows lobby

        current_offset = 0.0
        questions = questionnaire["questions"]
        buffer = questionnaire.get("interQuestionBufferSeconds", 5)

        for i, q in enumerate(questions):
            q_limit = q["timeLimitSeconds"]
            q_start = start_time + current_offset
            q_end = q_start + q_limit
            q_next_start = q_end + buffer

            if q_start <= now < q_end:
                # User connected during active question answering phase
                remaining = int(q_end - now)
                shuffle = next((s for s in contest.get("questionShuffles", []) if str(s["questionId"]) == str(q["_id"])), None)
                options = shuffle["shuffledOptions"] if shuffle else q["options"]
                
                try:
                    await websocket.send_json({
                        "event": "QUESTION_START",
                        "data": {
                            "questionIndex": i,
                            "questionId": str(q["_id"]),
                            "questionText": q["questionText"],
                            "options": options,
                            "timeLimitSeconds": remaining,
                            "initialScore": q["initialScore"]
                        }
                    })
                except Exception:
                    pass
                return

            elif q_end <= now < q_next_start:
                # User connected during inter-question buffer phase
                leaderboard = await self.get_leaderboard_data(contest_id, contest)
                correct_idx = 0
                shuffle = next((s for s in contest.get("questionShuffles", []) if str(s["questionId"]) == str(q["_id"])), None)
                if shuffle:
                    correct_text = q["options"][0]
                    try:
                        correct_idx = shuffle["shuffledOptions"].index(correct_text)
                    except ValueError:
                        pass
                
                try:
                    await websocket.send_json({
                        "event": "QUESTION_END",
                        "data": {
                            "questionIndex": i,
                            "questionId": str(q["_id"]),
                            "correctOptionIndex": correct_idx,
                            "leaderboard": leaderboard
                        }
                    })
                except Exception:
                    pass
                return

            current_offset += q_limit + buffer

    async def get_leaderboard_data(self, contest_id: str, contest: dict) -> List[dict]:
        db = get_db()
        contenders_ids = contest.get("contenders", [])
        if not contenders_ids:
            return []

        # Aggregate submissions by sum score
        pipeline = [
            {"$match": {"contestId": ObjectId(contest_id)}},
            {"$group": {"_id": "$userId", "totalScore": {"$sum": "$score"}}},
            {"$sort": {"totalScore": -1}}
        ]
        cursor = db.submissions.aggregate(pipeline)
        scores_by_user = {str(item["_id"]): item["totalScore"] for item in await cursor.to_list(length=1000)}

        # Fetch display names
        users_cursor = db.users.find({"_id": {"$in": [ObjectId(uid) for uid in contenders_ids]}})
        users = await users_cursor.to_list(length=1000)
        user_names = {str(u["_id"]): u["username"] for u in users}

        leaderboard = []
        for uid in contenders_ids:
            uid_str = str(uid)
            username = user_names.get(uid_str, "Anonymous")
            score = scores_by_user.get(uid_str, 0.0)
            leaderboard.append({"username": username, "score": round(float(score), 2)})

        # Sort: score DESC, username ASC
        leaderboard.sort(key=lambda x: (-x["score"], x["username"]))

        # Assign ranks
        for rank, entry in enumerate(leaderboard, 1):
            entry["rank"] = rank

        return leaderboard

    async def run_game_loop(self, contest_id: str):
        db = get_db()
        contest = await db.contests.find_one({"_id": ObjectId(contest_id)})
        if not contest:
            return

        questionnaire = await db.questionnaires.find_one({"title": contest["questionnaireTitle"]})
        if not questionnaire:
            return

        questions = questionnaire["questions"]
        buffer = questionnaire.get("interQuestionBufferSeconds", 5)

        # Generate options shuffles per question for this contest if they don't exist yet
        if not contest.get("questionShuffles"):
            shuffles = []
            for q in questions:
                shuffled_opts = list(q["options"])
                random.shuffle(shuffled_opts)
                shuffles.append({
                    "questionId": ObjectId(q["_id"]),
                    "shuffledOptions": shuffled_opts
                })
            await db.contests.update_one(
                {"_id": ObjectId(contest_id)},
                {
                    "$set": {
                        "status": ContestStatus.ACTIVE,
                        "questionShuffles": shuffles
                    }
                }
            )
            contest = await db.contests.find_one({"_id": ObjectId(contest_id)})

        # Broadcast CONTEST_STARTED event
        await self.broadcast(contest_id, {
            "event": "CONTEST_STARTED",
            "data": {"contestId": contest_id}
        })

        start_time = contest["scheduledStartTime"]

        for i, q in enumerate(questions):
            q_limit = q["timeLimitSeconds"]
            shuffle = next((s for s in contest["questionShuffles"] if str(s["questionId"]) == str(q["_id"])), None)
            options = shuffle["shuffledOptions"] if shuffle else q["options"]

            q_start_target = start_time + sum(questions[j]["timeLimitSeconds"] + buffer for j in range(i))
            
            # Wait for starting time
            now = time.time()
            if q_start_target > now:
                await asyncio.sleep(q_start_target - now)

            # Update current active index in database
            await db.contests.update_one(
                {"_id": ObjectId(contest_id)},
                {"$set": {"currentQuestionIndex": i}}
            )

            # Send QUESTION_START
            now = time.time()
            q_end_target = q_start_target + q_limit
            remaining = int(q_end_target - now)

            if remaining > 0:
                await self.broadcast(contest_id, {
                    "event": "QUESTION_START",
                    "data": {
                        "questionIndex": i,
                        "questionId": str(q["_id"]),
                        "questionText": q["questionText"],
                        "options": options,
                        "timeLimitSeconds": remaining,
                        "initialScore": q["initialScore"]
                    }
                })
                await asyncio.sleep(remaining)

            # QUESTION_END event with current standings
            leaderboard = await self.get_leaderboard_data(contest_id, contest)
            correct_idx = 0
            if shuffle:
                correct_text = q["options"][0]
                try:
                    correct_idx = shuffle["shuffledOptions"].index(correct_text)
                except ValueError:
                    pass

            await self.broadcast(contest_id, {
                "event": "QUESTION_END",
                "data": {
                    "questionIndex": i,
                    "questionId": str(q["_id"]),
                    "correctOptionIndex": correct_idx,
                    "leaderboard": leaderboard
                }
            })

            # Wait buffer pause
            now = time.time()
            next_start_target = q_end_target + buffer
            if next_start_target > now:
                await asyncio.sleep(next_start_target - now)

        # End Contest
        leaderboard = await self.get_leaderboard_data(contest_id, contest)
        total_contenders = len(contest.get("contenders", []))

        # Persist final leaderboard results
        await db.contests.update_one(
            {"_id": ObjectId(contest_id)},
            {
                "$set": {
                    "status": ContestStatus.COMPLETED,
                    "finalLeaderboard": leaderboard
                }
            }
        )

        # Broadcast CONTEST_ENDED with personalized user ranking
        await self.send_contest_ended(contest_id, leaderboard, total_contenders)

        # Remove running task from coordinator
        if contest_id in self.running_tasks:
            del self.running_tasks[contest_id]

    async def send_contest_ended(self, contest_id: str, leaderboard: list, total_contenders: int):
        if contest_id not in self.rooms:
            return
        
        for ws in list(self.rooms[contest_id]):
            user_id = ws.scope.get("user_id")
            my_rank = 0
            if user_id:
                db = get_db()
                user = await db.users.find_one({"_id": ObjectId(user_id)})
                if user:
                    username = user["username"]
                    for entry in leaderboard:
                        if entry["username"] == username:
                            my_rank = entry["rank"]
                            break
            
            try:
                await ws.send_json({
                    "event": "CONTEST_ENDED",
                    "data": {
                        "finalLeaderboard": leaderboard,
                        "myRank": my_rank,
                        "totalContenders": total_contenders
                    }
                })
            except Exception:
                pass

    async def scheduler_loop(self):
        while True:
            try:
                db = get_db()
                if db is None:
                    await asyncio.sleep(1)
                    continue

                now = time.time()

                # Start scheduled contests
                cursor = db.contests.find({
                    "status": ContestStatus.SCHEDULED,
                    "scheduledStartTime": {"$lte": now}
                })
                contests = await cursor.to_list(length=100)
                for contest in contests:
                    contest_id = str(contest["_id"])
                    if contest_id not in self.running_tasks:
                        task = asyncio.create_task(self.run_game_loop(contest_id))
                        self.running_tasks[contest_id] = task

                # Resume active contests in case server restarted mid-contest
                active_cursor = db.contests.find({
                    "status": ContestStatus.ACTIVE
                })
                active_contests = await active_cursor.to_list(length=100)
                for contest in active_contests:
                    contest_id = str(contest["_id"])
                    if contest_id not in self.running_tasks:
                        questionnaire = await db.questionnaires.find_one({"title": contest["questionnaireTitle"]})
                        if questionnaire:
                            total_duration = sum(q["timeLimitSeconds"] + questionnaire.get("interQuestionBufferSeconds", 5) for q in questionnaire["questions"])
                            end_time = contest["scheduledStartTime"] + total_duration
                            if now >= end_time:
                                # Contest expired while server was offline
                                leaderboard = await self.get_leaderboard_data(contest_id, contest)
                                await db.contests.update_one(
                                    {"_id": ObjectId(contest_id)},
                                    {"$set": {"status": ContestStatus.COMPLETED, "finalLeaderboard": leaderboard}}
                                )
                            else:
                                # Contest timeline is still active: resume game loop
                                task = asyncio.create_task(self.run_game_loop(contest_id))
                                self.running_tasks[contest_id] = task
            except Exception as e:
                # Log loop errors quietly in background
                pass
            await asyncio.sleep(1)

coordinator = GameCoordinator()
