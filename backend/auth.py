from datetime import datetime, timedelta
from typing import Optional
from jose import JWTError, jwt
from passlib.context import CryptContext
from fastapi import HTTPException, status
from models import User, TokenData

# Configuration
SECRET_KEY = "your-secret-key-change-in-production"  # In production, use environment variable
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_DAYS = 30  # 30 days

# Password hashing
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# In-memory user storage (replace with database in production)
users_db: dict[str, User] = {}

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a password against its hash."""
    return pwd_context.verify(plain_password, hashed_password)

def get_password_hash(password: str) -> str:
    """Hash a password."""
    return pwd_context.hash(password)

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
    user = users_db.get(username)
    if not user:
        return None
    if not verify_password(pin, user.pin):
        return None
    return user

def get_user(username: str) -> Optional[User]:
    """Get a user by username."""
    print(f"DEBUG: get_user called with username: {username}")
    print(f"DEBUG: Current users_db: {list(users_db.keys())}")
    user = users_db.get(username)
    print(f"DEBUG: get_user result: {user}")
    return user

def create_user(username: str, pin: str) -> User:
    """Create a new user."""
    print(f"DEBUG: create_user called with username: {username}")
    print(f"DEBUG: Current users_db before creation: {list(users_db.keys())}")
    
    if username in users_db:
        print(f"DEBUG: Username {username} already exists")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Username already registered"
        )
    
    hashed_pin = get_password_hash(pin)
    user = User(username=username, pin=hashed_pin)
    users_db[username] = user
    print(f"DEBUG: User {username} added to users_db")
    print(f"DEBUG: users_db after adding user: {list(users_db.keys())}")
    return user

def validate_pin(pin: str) -> bool:
    """Validate PIN format (4 digits)."""
    return pin.isdigit() and len(pin) == 4

def validate_username(username: str) -> bool:
    """Validate username format."""
    return len(username.strip()) >= 3 and len(username.strip()) <= 20
