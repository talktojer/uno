from sqlalchemy import Column, DateTime, Integer, String, func

from database import Base


class UserModel(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(50), unique=True, nullable=False, index=True)
    hashed_pin = Column(String(255), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

