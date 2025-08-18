from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from typing import Dict, List, Optional, Set
import json
import random
import asyncio
from pydantic import BaseModel
from enum import Enum
import string
import secrets

app = FastAPI(title="UNO Game Backend", version="1.0.0")

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*", "https://uno.jersweb.net", "http://uno.jersweb.net"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Game Models
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
    winner: Optional[str] = None

# Game Logic
class UNOGame:
    def __init__(self, game_id: str):
        self.game_id = game_id
        self.game_code = self._generate_game_code()
        self.players: List[Player] = []
        self.deck: List[Card] = []
        self.discard_pile: List[Card] = []
        self.current_player_index = 0
        self.current_color: CardColor = CardColor.RED
        self.current_direction = 1
        self.game_started = False
        self.winner: Optional[str] = None
        self._initialize_deck()
    
    def _generate_game_code(self) -> str:
        """Generate a random 5-character game code"""
        # Use alphanumeric characters (0-9, A-Z)
        characters = string.ascii_uppercase + string.digits
        return ''.join(secrets.choice(characters) for _ in range(5))
    
    def _initialize_deck(self):
        """Initialize the UNO deck with all cards"""
        self.deck = []
        
        # Add number cards (0-9) for each color
        for color in [CardColor.RED, CardColor.BLUE, CardColor.GREEN, CardColor.YELLOW]:
            # One 0 card
            self.deck.append(Card(color=color, type=CardType.NUMBER, value=0))
            # Two of each 1-9
            for value in range(1, 10):
                self.deck.append(Card(color=color, type=CardType.NUMBER, value=value))
                self.deck.append(Card(color=color, type=CardType.NUMBER, value=value))
            
            # Add action cards (2 of each)
            for _ in range(2):
                self.deck.append(Card(color=color, type=CardType.SKIP))
                self.deck.append(Card(color=color, type=CardType.REVERSE))
                self.deck.append(Card(color=color, type=CardType.DRAW2))
        
        # Add wild cards (4 of each)
        for _ in range(4):
            self.deck.append(Card(color=CardColor.BLACK, type=CardType.WILD))
            self.deck.append(Card(color=CardColor.BLACK, type=CardType.WILD_DRAW4))
    
    def shuffle_deck(self):
        """Shuffle the deck"""
        random.shuffle(self.deck)
    
    def deal_cards(self):
        """Deal 7 cards to each player"""
        for player in self.players:
            player.cards = []
            for _ in range(7):
                if self.deck:
                    player.cards.append(self.deck.pop())
    
    def start_game(self):
        """Start the game"""
        if len(self.players) != 2:
            raise ValueError("Game requires exactly 2 players")
        
        self.shuffle_deck()
        self.deal_cards()
        
        # Place first card on discard pile
        while True:
            card = self.deck.pop()
            if card.type == CardType.NUMBER:
                self.discard_pile.append(card)
                self.current_color = card.color
                break
            else:
                self.deck.insert(0, card)
        
        # Clear all turn flags first
        for player in self.players:
            player.is_current_turn = False
        
        # Set first player's turn
        self.current_player_index = 0
        self.players[0].is_current_turn = True
        self.game_started = True
    
    def can_play_card(self, card: Card, player_index: int) -> bool:
        """Check if a card can be played"""
        if not self.game_started or self.winner:
            return False
        
        if player_index != self.current_player_index:
            return False
        
        # Wild cards can always be played
        if card.type in [CardType.WILD, CardType.WILD_DRAW4]:
            return True
        
        # Check color match
        if card.color == self.current_color:
            return True
        
        # Check value match for number cards
        if (card.type == CardType.NUMBER and 
            self.discard_pile and 
            self.discard_pile[-1].type == CardType.NUMBER and
            card.value == self.discard_pile[-1].value):
            return True
        
        # Check type match for action cards
        if (card.type != CardType.NUMBER and 
            self.discard_pile and 
            card.type == self.discard_pile[-1].type):
            return True
        
        return False
    
    def play_card(self, player_index: int, card_index: int, new_color: Optional[CardColor] = None) -> Dict:
        """Play a card and return the result"""
        if not self.can_play_card(self.players[player_index].cards[card_index], player_index):
            raise ValueError("Cannot play this card")
        
        player = self.players[player_index]
        card = player.cards.pop(card_index)
        
        # Add to discard pile
        self.discard_pile.append(card)
        
        # Handle card effects
        if card.type == CardType.NUMBER:
            self.current_color = card.color
        elif card.type == CardType.SKIP:
            self.current_color = card.color
            self._next_player()
        elif card.type == CardType.REVERSE:
            self.current_color = card.color
            self.current_direction *= -1
        elif card.type == CardType.DRAW2:
            self.current_color = card.color
            self._next_player()
            # Draw 2 cards for next player
            next_player = self.players[self.current_player_index]
            for _ in range(2):
                if self.deck:
                    next_player.cards.append(self.deck.pop())
        elif card.type == CardType.WILD:
            if new_color:
                self.current_color = new_color
        elif card.type == CardType.WILD_DRAW4:
            if new_color:
                self.current_color = new_color
            self._next_player()
            # Draw 4 cards for next player
            next_player = self.players[self.current_player_index]
            for _ in range(4):
                if self.deck:
                    next_player.cards.append(self.deck.pop())
        
        # Check for winner
        if len(player.cards) == 0:
            self.winner = player.id
            return {"game_over": True, "winner": player.id}
        
        # Move to next player if not skipped
        if card.type not in [CardType.SKIP, CardType.DRAW2, CardType.WILD_DRAW4]:
            self._next_player()
        
        return {"success": True, "next_player": self.current_player_index}
    
    def _next_player(self):
        """Move to the next player"""
        # Clear current turn flag from all players
        for player in self.players:
            player.is_current_turn = False
        
        # Move to next player
        self.current_player_index = (self.current_player_index + self.current_direction) % len(self.players)
        
        # Set turn flag for new current player
        self.players[self.current_player_index].is_current_turn = True
    
    def draw_card(self, player_index: int) -> Optional[Card]:
        """Draw a card for a player"""
        if player_index != self.current_player_index or not self.game_started:
            return None
        
        if not self.deck:
            # Reshuffle discard pile (except top card)
            if len(self.discard_pile) > 1:
                top_card = self.discard_pile.pop()
                self.deck = self.discard_pile.copy()
                self.discard_pile = [top_card]
                self.shuffle_deck()
            else:
                # If only one card in discard pile, can't reshuffle
                return None
        
        if self.deck:
            card = self.deck.pop()
            self.players[player_index].cards.append(card)
            # Don't advance turn here - let the WebSocket handler do it
            return card
        return None
    
    def get_game_state(self) -> GameState:
        """Get current game state"""
        return GameState(
            game_id=self.game_id,
            game_code=self.game_code,
            players=self.players,
            current_player_index=self.current_player_index,
            deck=self.deck,
            discard_pile=self.discard_pile,
            current_color=self.current_color,
            current_direction=self.current_direction,
            game_started=self.game_started,
            winner=self.winner
        )
    
    def get_draw_pile_count(self) -> int:
        """Get the number of cards in the draw pile"""
        return len(self.deck)

# Game Management
games: Dict[str, UNOGame] = {}
games_by_code: Dict[str, str] = {}  # Maps game codes to game IDs
active_connections: Dict[str, WebSocket] = {}

@app.get("/")
async def root():
    return {"message": "UNO Game Backend"}

@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": "uno-backend"}

@app.post("/api/games/create")
async def create_game():
    """Create a new game"""
    game_id = f"game_{len(games) + 1}"
    game = UNOGame(game_id)
    
    # Ensure unique game code
    while game.game_code in games_by_code:
        game.game_code = game._generate_game_code()
    
    games[game_id] = game
    games_by_code[game.game_code] = game_id
    
    # Broadcast updated game list to all connected players
    await _broadcast_game_list_update()
    
    return {
        "game_id": game_id, 
        "game_code": game.game_code,
        "message": "Game created successfully"
    }

@app.get("/api/games")
async def list_games():
    """List all available games"""
    available_games = []
    for game_id, game in games.items():
        available_games.append({
            "game_id": game_id,
            "game_code": game.game_code,
            "player_count": len(game.players),
            "max_players": 2,
            "game_started": game.game_started,
            "status": "full" if len(game.players) >= 2 else "waiting" if not game.game_started else "in_progress"
        })
    return {"games": available_games}

@app.get("/api/games/code/{game_code}")
async def get_game_by_code(game_code: str):
    """Get game information by game code"""
    if game_code not in games_by_code:
        raise HTTPException(status_code=404, detail="Game code not found")
    
    game_id = games_by_code[game_code]
    game = games[game_id]
    
    return {
        "game_id": game_id,
        "game_code": game_code,
        "player_count": len(game.players),
        "max_players": 2,
        "game_started": game.game_started,
        "status": "full" if len(game.players) >= 2 else "waiting" if not game.game_started else "in_progress"
    }

@app.get("/api/games/{game_id}")
async def get_game_state(game_id: str):
    """Get current game state"""
    if game_id not in games:
        raise HTTPException(status_code=404, detail="Game not found")
    
    return games[game_id].get_game_state()

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

@app.post("/api/games/{game_id}/join")
async def join_game(game_id: str, request: JoinGameRequest):
    """Join a game by game ID"""
    if game_id not in games:
        raise HTTPException(status_code=404, detail="Game not found")
    
    game = games[game_id]
    
    # Check if there's an available slot (either empty or disconnected player)
    available_slots = []
    for i, player in enumerate(game.players):
        if player.id not in active_connections:
            available_slots.append(i)
    
    if len(game.players) >= 2 and not available_slots:
        raise HTTPException(status_code=400, detail="Game is full")
    
    if game.game_started and not available_slots:
        raise HTTPException(status_code=400, detail="Game already started and full")
    
    # If there's an available slot, replace the disconnected player
    if available_slots:
        slot_index = available_slots[0]
        old_player_id = game.players[slot_index].id
        
        # Create new player with the same slot
        player_id = f"player_{slot_index + 1}"
        player = Player(id=player_id, name=request.player_name, cards=[])
        
        # If game was started, give the new player the same cards as the old player
        if game.game_started:
            player.cards = game.players[slot_index].cards.copy()
            # Reset turn if it was the disconnected player's turn
            if slot_index == game.current_player_index:
                player.is_current_turn = True
        
        game.players[slot_index] = player
        
        # Remove old player from active connections
        if old_player_id in active_connections:
            del active_connections[old_player_id]
        
        message = f"Replaced disconnected player. {request.player_name} joined the game."
    else:
        # Create new player in new slot
        player_id = f"player_{len(game.players) + 1}"
        player = Player(id=player_id, name=request.player_name, cards=[])
        game.players.append(player)
        message = f"{request.player_name} joined the game."
    
    # Broadcast updated game list to all connected players
    await _broadcast_game_list_update()
    
    # If this is a replacement in a started game, broadcast the updated game state
    if game.game_started:
        await _broadcast_game_state(game_id, {
            "type": "player_replaced",
            "message": message,
            "new_player": player.model_dump()
        })
    
    return {"player_id": player_id, "message": message}

@app.post("/api/games/join-by-code")
async def join_game_by_code(request: JoinGameByCodeRequest):
    """Join a game by 5-character game code"""
    game_code = request.game_code
    player_name = request.player_name
    
    if game_code not in games_by_code:
        raise HTTPException(status_code=404, detail="Game code not found")
    
    game_id = games_by_code[game_code]
    game = games[game_id]
    
    # Check if there's an available slot (either empty or disconnected player)
    available_slots = []
    for i, player in enumerate(game.players):
        if player.id not in active_connections:
            available_slots.append(i)
    
    if len(game.players) >= 2 and not available_slots:
        raise HTTPException(status_code=400, detail="Game is full")
    
    if game.game_started and not available_slots:
        raise HTTPException(status_code=400, detail="Game already started and full")
    
    # If there's an available slot, replace the disconnected player
    if available_slots:
        slot_index = available_slots[0]
        old_player_id = game.players[slot_index].id
        
        # Create new player with the same slot
        player_id = f"player_{slot_index + 1}"
        player = Player(id=player_id, name=player_name, cards=[])
        
        # If game was started, give the new player the same cards as the old player
        if game.game_started:
            player.cards = game.players[slot_index].cards.copy()
            # Reset turn if it was the disconnected player's turn
            if slot_index == game.current_player_index:
                player.is_current_turn = True
        
        game.players[slot_index] = player
        
        # Remove old player from active connections
        if old_player_id in active_connections:
            del active_connections[old_player_id]
        
        message = f"Replaced disconnected player. {player_name} joined the game."
    else:
        # Create new player in new slot
        player_id = f"player_{len(game.players) + 1}"
        player = Player(id=player_id, name=player_name, cards=[])
        game.players.append(player)
        message = f"{player_name} joined the game."
    
    # Broadcast updated game list to all connected players
    await _broadcast_game_list_update()
    
    # If this is a replacement in a started game, broadcast the updated game state
    if game.game_started:
        await _broadcast_game_state(game_id, {
            "type": "player_replaced",
            "message": message,
            "new_player": player.model_dump()
        })
    
    return {"player_id": player_id, "game_id": game_id, "message": message}

@app.post("/api/games/{game_id}/start")
async def start_game(game_id: str):
    """Start the game"""
    if game_id not in games:
        raise HTTPException(status_code=404, detail="Game not found")
    
    game = games[game_id]
    if len(game.players) != 2:
        raise HTTPException(status_code=400, detail="Need exactly 2 players to start")
    
    game.start_game()
    return {"message": "Game started successfully"}

@app.post("/api/games/{game_id}/play")
async def play_card(game_id: str, request: PlayCardRequest):
    """Play a card"""
    if game_id not in games:
        raise HTTPException(status_code=404, detail="Game not found")
    
    game = games[game_id]
    player_index = next((i for i, p in enumerate(game.players) if p.id == request.player_id), None)
    
    if player_index is None:
        raise HTTPException(status_code=404, detail="Player not found")
    
    try:
        result = game.play_card(player_index, request.card_index, request.new_color)
        return result
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.post("/api/games/{game_id}/draw")
async def draw_card(game_id: str, request: DrawCardRequest):
    """Draw a card"""
    if game_id not in games:
        raise HTTPException(status_code=404, detail="Game not found")
    
    game = games[game_id]
    player_index = next((i for i, p in enumerate(game.players) if p.id == request.player_id), None)
    
    if player_index is None:
        raise HTTPException(status_code=404, detail="Player not found")
    
    card = game.draw_card(player_index)
    if card:
        # Move to next player after drawing
        game._next_player()
        return {"card": card, "next_player": game.current_player_index}
    else:
        raise HTTPException(status_code=400, detail="Cannot draw card")

# WebSocket endpoint for lobby updates (game list)
@app.websocket("/ws/lobby/{player_id}")
async def lobby_websocket_endpoint(websocket: WebSocket, player_id: str):
    await websocket.accept()
    active_connections[player_id] = websocket
    
    # Send initial game list
    await _send_game_list_to_player(websocket)
    
    try:
        while True:
            # Keep connection alive and handle any incoming messages
            data = await websocket.receive_text()
            message = json.loads(data)
            
            # Handle different message types
            if message.get("type") == "ping":
                await websocket.send_text(json.dumps({"type": "pong"}))
            
    except WebSocketDisconnect:
        if player_id in active_connections:
            del active_connections[player_id]

# WebSocket endpoint for real-time game updates
@app.websocket("/ws/{game_id}/{player_id}")
async def websocket_endpoint(websocket: WebSocket, game_id: str, player_id: str):
    await websocket.accept()
    active_connections[player_id] = websocket
    
    # Send initial game state to the newly connected player
    if game_id in games:
        game = games[game_id]
        game_state = game.get_game_state()
        await websocket.send_text(json.dumps({
            "type": "game_update",
            "game_state": game_state.model_dump(),  # Use model_dump() for Pydantic v2
        }))
    
    try:
        while True:
            # Handle incoming messages
            data = await websocket.receive_text()
            message = json.loads(data)
            
            # Handle different message types
            if message.get("type") == "ping":
                await websocket.send_text(json.dumps({"type": "pong"}))
            elif message.get("type") == "play_card":
                # Handle playing a card
                card_index = message.get("card_index")
                new_color = message.get("new_color")
                
                if game_id in games and card_index is not None:
                    game = games[game_id]
                    player_index = next((i for i, p in enumerate(game.players) if p.id == player_id), None)
                    
                    if player_index is not None:
                        try:
                            # Convert string color to CardColor enum if provided
                            card_color = None
                            if new_color:
                                try:
                                    card_color = CardColor(new_color)
                                except ValueError:
                                    await websocket.send_text(json.dumps({
                                        "type": "error",
                                        "message": "Invalid color specified"
                                    }))
                                    continue
                            
                            result = game.play_card(player_index, card_index, card_color)
                            # Broadcast updated game state to all players
                            await _broadcast_game_state(game_id, {
                                "type": "card_played",
                                "result": result
                            })
                        except ValueError as e:
                            await websocket.send_text(json.dumps({
                                "type": "error",
                                "message": str(e)
                            }))
                
            elif message.get("type") == "start_game":
                # Handle starting the game
                if game_id in games:
                    game = games[game_id]
                    if len(game.players) == 2:
                        game.start_game()
                        # Broadcast updated game state to all players
                        await _broadcast_game_state(game_id)
                        # Also send a separate start confirmation
                        for player in game.players:
                            if player.id in active_connections:
                                try:
                                    await active_connections[player.id].send_text(json.dumps({
                                        "type": "game_started",
                                        "message": "Game started successfully"
                                    }))
                                except:
                                    if player.id in active_connections:
                                        del active_connections[player.id]
                    else:
                        await websocket.send_text(json.dumps({
                            "type": "error",
                            "message": "Need exactly 2 players to start"
                        }))
                else:
                    await websocket.send_text(json.dumps({
                        "type": "error",
                        "message": "Game not found"
                    }))
                    
            elif message.get("type") == "draw_card":
                # Handle drawing a card
                if game_id in games:
                    game = games[game_id]
                    player_index = next((i for i, p in enumerate(game.players) if p.id == player_id), None)
                    
                    if player_index is not None:
                        card = game.draw_card(player_index)
                        if card:
                            # Advance turn after drawing
                            game._next_player()
                            await _broadcast_game_state(game_id, {
                                "type": "card_drawn",
                                "card": card.model_dump(),
                                "next_player": game.current_player_index
                            })
                        else:
                            await websocket.send_text(json.dumps({
                                "type": "error",
                                "message": "Cannot draw card"
                            }))
            
    except WebSocketDisconnect:
        if player_id in active_connections:
            del active_connections[player_id]
            
        # Check if this was a game player and update game status
        if game_id in games:
            game = games[game_id]
            # Broadcast updated game list to show available slots
            await _broadcast_game_list_update()
            
            # If game was started and player disconnected, notify other players
            if game.game_started:
                await _broadcast_game_state(game_id, {
                    "type": "player_disconnected",
                    "message": f"Player {player_id} disconnected from the game",
                    "disconnected_player_id": player_id
                })

async def _broadcast_game_state(game_id: str, additional_data: dict = None):
    """Broadcast game state to all players in a game"""
    if game_id not in games:
        return
    
    game = games[game_id]
    game_state = game.get_game_state()
    
    # Prepare the message
    if additional_data and 'type' in additional_data:
        # If additional data has a type, use that instead of defaulting to game_update
        message = {
            "type": additional_data['type'],
            "game_state": game_state.model_dump(),  # Use model_dump() for Pydantic v2
        }
        # Add other additional data fields
        for key, value in additional_data.items():
            if key != 'type':
                message[key] = value
    else:
        # Default to game_update type
        message = {
            "type": "game_update",
            "game_state": game_state.model_dump(),  # Use model_dump() for Pydantic v2
        }
        # Add additional data if provided
        if additional_data:
            message.update(additional_data)
    
    # Send to all players in the game
    for player in game.players:
        if player.id in active_connections:
            try:
                await active_connections[player.id].send_text(json.dumps(message))
            except Exception as e:
                print(f"Error sending to player {player.id}: {e}")
                # Remove dead connections
                if player.id in active_connections:
                    del active_connections[player.id]

async def _send_game_list_to_player(websocket: WebSocket):
    """Send current game list to a specific player"""
    available_games = []
    for game_id, game in games.items():
        # Count active (connected) players
        active_players = sum(1 for p in game.players if p.id in active_connections)
        
        # Determine game status
        if len(game.players) >= 2 and active_players >= 2:
            status = "full"
        elif game.game_started and active_players < 2:
            status = "waiting_for_replacement"
        elif not game.game_started:
            status = "waiting"
        else:
            status = "in_progress"
        
        available_games.append({
            "game_id": game_id,
            "game_code": game.game_code,
            "player_count": len(game.players),
            "active_players": active_players,
            "max_players": 2,
            "game_started": game.game_started,
            "status": status
        })
    
    message = {
        "type": "game_list_update",
        "games": available_games
    }
    
    try:
        await websocket.send_text(json.dumps(message))
    except Exception as e:
        print(f"Error sending game list to player: {e}")

async def _broadcast_game_list_update():
    """Broadcast updated game list to all connected players"""
    available_games = []
    for game_id, game in games.items():
        # Count active (connected) players
        active_players = sum(1 for p in game.players if p.id in active_connections)
        
        # Determine game status
        if len(game.players) >= 2 and active_players >= 2:
            status = "full"
        elif game.game_started and active_players < 2:
            status = "waiting_for_replacement"
        elif not game.game_started:
            status = "waiting"
        else:
            status = "in_progress"
        
        available_games.append({
            "game_id": game_id,
            "game_code": game.game_code,
            "player_count": len(game.players),
            "active_players": active_players,
            "max_players": 2,
            "game_started": game.game_started,
            "status": status
        })
    
    message = {
        "type": "game_list_update",
        "games": available_games
    }
    
    # Send to all connected players
    for player_id, websocket in active_connections.items():
        try:
            await websocket.send_text(json.dumps(message))
        except Exception as e:
            print(f"Error sending game list update to {player_id}: {e}")
            # Remove dead connections
            if player_id in active_connections:
                del active_connections[player_id]

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
