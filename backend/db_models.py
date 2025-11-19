from sqlalchemy import Column, DateTime, Integer, String, Text, func

from database import Base


class UserModel(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(50), unique=True, nullable=False, index=True)
    hashed_pin = Column(String(255), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class GameModel(Base):
    __tablename__ = "games"

    id = Column(String, primary_key=True, index=True)
    game_code = Column(String(5), unique=True, nullable=False, index=True)
    game_state_json = Column(Text, nullable=False)  # Store serialized game state as JSON string
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

