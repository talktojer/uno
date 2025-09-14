from pydantic import BaseModel
from enum import Enum
from typing import List, Optional


class CardColor(str, Enum):
    RED = "red"
    BLUE = "blue"
    GREEN = "green"
    YELLOW = "yellow"
    BLACK = "black"  # For wild and draw4 cards


class CardType(str, Enum):
    NUMBER = "number"
    SKIP = "skip"
    REVERSE = "reverse"
    DRAW2 = "draw2"
    WILD = "wild"
    WILD_DRAW4 = "wild_draw4"


class Card(BaseModel):
    color: CardColor
    type: CardType
    value: Optional[int] = None  # Only for number cards
    
    def model_dump(self, *args, **kwargs):
        return {
            "color": self.color,
            "type": self.type,
            "value": self.value
        }


class Player(BaseModel):
    id: str
    name: str
    cards: List[Card]
    is_current_turn: bool = False
    
    def model_dump(self, *args, **kwargs):
        return {
            "id": self.id,
            "name": self.name,
            "cards": [card.model_dump() for card in self.cards],
            "is_current_turn": self.is_current_turn
        }


class GameState(BaseModel):
    game_id: str
    game_code: str
    players: List[Player]
    current_player_index: int
    deck: List[Card]
    discard_pile: List[Card]
    current_color: CardColor
    current_direction: int  # 1 for clockwise, -1 for counter-clockwise
    game_started: bool = False
    game_ended: bool = False
    winner: Optional[str] = None


# Request Models
class JoinGameRequest(BaseModel):
    player_name: str


class JoinGameByCodeRequest(BaseModel):
    game_code: str
    player_name: str


class PlayCardRequest(BaseModel):
    player_id: str
    card_index: int
    new_color: Optional[CardColor] = None


class DrawCardRequest(BaseModel):
    player_id: str


class ReclaimSlotRequest(BaseModel):
    original_player_id: str
    player_name: str
