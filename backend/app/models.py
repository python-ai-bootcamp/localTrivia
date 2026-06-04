from pydantic import BaseModel, Field, BeforeValidator
from typing import Annotated, List, Optional
from datetime import datetime
from enum import Enum
from bson import ObjectId

# Represents an ObjectId field in MongoDB, converted to string for JSON serialization
PyObjectId = Annotated[str, BeforeValidator(str)]

# User Models
class UserRegisterRequest(BaseModel):
    deviceToken: str
    username: str

class UserResponse(BaseModel):
    id: PyObjectId = Field(alias="_id")
    deviceToken: str
    username: str
    avatarUrl: Optional[str] = None
    addedContests: List[PyObjectId] = []
    createdAt: datetime

    class Config:
        populate_by_name = True
        json_encoders = {ObjectId: str}

# Question Models
class SingleQuestion(BaseModel):
    id: PyObjectId = Field(default_factory=lambda: str(ObjectId()), alias="_id")
    questionText: str
    options: List[str]  # 4 options, first is correct
    timeLimitSeconds: int
    initialScore: int

    class Config:
        populate_by_name = True
        json_encoders = {ObjectId: str}

class SingleQuestionCreate(BaseModel):
    questionText: str
    options: List[str]
    timeLimitSeconds: int
    initialScore: int

# Questionnaire Models
class QuestionnaireCreate(BaseModel):
    title: str
    questions: List[SingleQuestionCreate]
    interQuestionBufferSeconds: Optional[int] = 5

class QuestionnaireResponse(BaseModel):
    id: PyObjectId = Field(alias="_id")
    title: str
    questions: List[SingleQuestion]
    interQuestionBufferSeconds: int
    createdAt: datetime

    class Config:
        populate_by_name = True
        json_encoders = {ObjectId: str}

# Contest Models
class ContestStatus(str, Enum):
    SCHEDULED = "SCHEDULED"
    ACTIVE = "ACTIVE"
    COMPLETED = "COMPLETED"

class ContestCreate(BaseModel):
    questionnaire_title: str
    scheduledStartTime: int  # Epoch seconds
    entryFee: int
    qr: str  # Full URL

class QuestionShuffle(BaseModel):
    questionId: PyObjectId
    shuffledOptions: List[str]

    class Config:
        populate_by_name = True
        json_encoders = {ObjectId: str}

class LeaderboardEntry(BaseModel):
    username: str
    score: float
    rank: int
    isMe: Optional[bool] = None

class ContestResponse(BaseModel):
    id: PyObjectId = Field(alias="_id")
    questionnaireTitle: str
    scheduledStartTime: int
    status: ContestStatus
    contenders: List[PyObjectId] = []
    entryFee: int
    prizePool: float
    qr: str
    qrCodeBase64: str
    currentQuestionIndex: int
    questionShuffles: List[QuestionShuffle] = []
    finalLeaderboard: Optional[List[LeaderboardEntry]] = None
    createdAt: datetime

    class Config:
        populate_by_name = True
        json_encoders = {ObjectId: str}

# Submission Models
class SubmissionRequest(BaseModel):
    questionId: str
    selectedOptionIndex: int
    timeTakenMs: int

class SubmissionResponse(BaseModel):
    isCorrect: bool
    score: float
