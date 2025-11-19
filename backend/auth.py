from datetime import datetime, timedelta
from typing import List, Optional
from jose import JWTError, jwt
from passlib.context import CryptContext
from fastapi import HTTPException, status
from models import User, TokenData
from sqlalchemy.orm import Session

from database import SessionLocal
from db_models import UserModel

# Configuration
SECRET_KEY = "your-secret-key-change-in-production"  # In production, use environment variable
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_DAYS = 30  # 30 days

# Password hashing
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def _truncate_password(password: str) -> str:
    """Truncate password to 72 bytes (bcrypt limit) while preserving UTF-8 encoding."""
    password_bytes = password.encode('utf-8')
    if len(password_bytes) > 72:
        # Truncate to 72 bytes, ensuring we don't break UTF-8 sequences
        truncated_bytes = password_bytes[:72]
        # Remove any incomplete UTF-8 sequences at the end
        while truncated_bytes and truncated_bytes[-1] & 0b11000000 == 0b10000000:
            truncated_bytes = truncated_bytes[:-1]
        return truncated_bytes.decode('utf-8', errors='ignore')
    return password

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a password against its hash."""
    # Truncate to match what was stored during hashing
    truncated_password = _truncate_password(plain_password)
    return pwd_context.verify(truncated_password, hashed_password)

def get_password_hash(password: str) -> str:
    """Hash a password, truncating to 72 bytes if necessary (bcrypt limit)."""
    # Truncate password to 72 bytes before hashing
    truncated_password = _truncate_password(password)
    return pwd_context.hash(truncated_password)

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    """Create a JWT access token."""
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(days=ACCESS_TOKEN_EXPIRE_DAYS)
    
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt

def verify_token(token: str) -> TokenData:
    """Verify and decode a JWT token."""
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        if username is None:
            raise ValueError("No username in token")
        token_data = TokenData(username=username)
    except JWTError as e:
        raise ValueError(f"Invalid token: {e}")
    
    return token_data

def authenticate_user(username: str, pin: str) -> Optional[User]:
    """Authenticate a user with username and PIN."""
    user = get_user(username)
    if not user:
        return None
    if not verify_password(pin, user.pin):
        return None
    return user

def get_user(username: str) -> Optional[User]:
    """Get a user by username."""
    with SessionLocal() as db:
        record = db.query(UserModel).filter(UserModel.username == username).first()
        if record:
            return _to_user_schema(record)
    return None

def create_user(username: str, pin: str) -> User:
    """Create a new user."""
    with SessionLocal() as db:
        if _username_exists(db, username):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Username already registered"
            )

        hashed_pin = get_password_hash(pin)
        record = UserModel(username=username, hashed_pin=hashed_pin)
        db.add(record)
        db.commit()
        db.refresh(record)
        return _to_user_schema(record)

def validate_pin(pin: str) -> bool:
    """Validate PIN format (4 digits)."""
    return pin.isdigit() and len(pin) == 4

def validate_username(username: str) -> bool:
    """Validate username format."""
    return len(username.strip()) >= 3 and len(username.strip()) <= 20

def list_usernames() -> List[str]:
    """Return all usernames for debugging purposes."""
    with SessionLocal() as db:
        return [user.username for user in db.query(UserModel).order_by(UserModel.username).all()]

def _username_exists(db: Session, username: str) -> bool:
    return db.query(UserModel.id).filter(UserModel.username == username).first() is not None

def _to_user_schema(record: UserModel) -> User:
    """Map a SQLAlchemy user record to the Pydantic schema."""
    created_at = record.created_at or datetime.utcnow()
    return User(username=record.username, pin=record.hashed_pin, created_at=created_at)
