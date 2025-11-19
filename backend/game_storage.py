import json
from typing import Optional
from sqlalchemy.orm import Session
from db_models import GameModel
from game_logic import UNOGame
from models import Card, Player, GameState, CardColor, CardType


def _serialize_game(game: UNOGame) -> str:
    """Serialize a UNOGame instance to JSON string"""
    game_state = game.get_game_state()
    # Convert to dict using model_dump for Pydantic v2
    state_dict = game_state.model_dump()
    return json.dumps(state_dict)


def _deserialize_game(game_id: str, game_code: str, state_json: str) -> UNOGame:
    """Deserialize JSON string back to UNOGame instance"""
    state_dict = json.loads(state_json)
    
    # Reconstruct GameState from dict
    # Convert cards from dicts to Card objects
    def dict_to_card(card_dict):
        return Card(
            color=CardColor(card_dict["color"]),
            type=CardType(card_dict["type"]),
            value=card_dict.get("value")
        )
    
    # Convert players from dicts to Player objects
    players = []
    for player_dict in state_dict["players"]:
        cards = [dict_to_card(card_dict) for card_dict in player_dict["cards"]]
        player = Player(
            id=player_dict["id"],
            name=player_dict["name"],
            cards=cards,
            is_current_turn=player_dict.get("is_current_turn", False)
        )
        players.append(player)
    
    # Convert deck and discard_pile
    deck = [dict_to_card(card_dict) for card_dict in state_dict["deck"]]
    discard_pile = [dict_to_card(card_dict) for card_dict in state_dict["discard_pile"]]
    
    # Create UNOGame instance
    game = UNOGame(game_id)
    game.game_code = game_code
    game.players = players
    game.deck = deck
    game.discard_pile = discard_pile
    game.current_player_index = state_dict["current_player_index"]
    game.current_color = CardColor(state_dict["current_color"])
    game.current_direction = state_dict["current_direction"]
    game.game_started = state_dict.get("game_started", False)
    game.game_ended = state_dict.get("game_ended", False)
    game.winner = state_dict.get("winner")
    
    return game


def save_game_to_db(db: Session, game: UNOGame) -> None:
    """Save a game to the database"""
    state_json = _serialize_game(game)
    
    # Check if game exists
    db_game = db.query(GameModel).filter(GameModel.id == game.game_id).first()
    
    if db_game:
        # Update existing game
        db_game.game_code = game.game_code
        db_game.game_state_json = state_json
    else:
        # Create new game
        db_game = GameModel(
            id=game.game_id,
            game_code=game.game_code,
            game_state_json=state_json
        )
        db.add(db_game)
    
    db.commit()


def load_game_from_db(db: Session, game_id: str) -> Optional[UNOGame]:
    """Load a game from the database by game_id"""
    db_game = db.query(GameModel).filter(GameModel.id == game_id).first()
    
    if not db_game:
        return None
    
    return _deserialize_game(db_game.id, db_game.game_code, db_game.game_state_json)


def get_game_by_code_from_db(db: Session, game_code: str) -> Optional[str]:
    """Get game_id by game_code from the database"""
    db_game = db.query(GameModel).filter(GameModel.game_code == game_code).first()
    
    if not db_game:
        return None
    
    return db_game.id


def delete_game_from_db(db: Session, game_id: str) -> None:
    """Delete a game from the database"""
    db_game = db.query(GameModel).filter(GameModel.id == game_id).first()
    
    if db_game:
        db.delete(db_game)
        db.commit()


def list_games_from_db(db: Session) -> list:
    """List all games from the database"""
    db_games = db.query(GameModel).all()
    return db_games

