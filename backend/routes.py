from fastapi import APIRouter, HTTPException, Depends, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from typing import Dict
from sqlalchemy.orm import Session
import secrets
from models import JoinGameRequest, JoinGameByCodeRequest, PlayCardRequest, DrawCardRequest, ReclaimSlotRequest, LoginRequest, SignupRequest, TokenResponse
from game_logic import UNOGame
from utils import games, games_by_code, active_connections, player_identities, disconnected_players, player_sessions, game_player_ownership, broadcast_game_list_update, broadcast_game_state, cleanup_game_data, get_game, save_game
from database import get_db
from game_storage import get_game_by_code_from_db, save_game_to_db
from auth import authenticate_user, create_user, create_access_token, verify_token, get_user, validate_pin, validate_username, list_usernames

router = APIRouter()
security = HTTPBearer()

# Dependency to get current user from token
async def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)):
    token = credentials.credentials
    try:
        print(f"DEBUG: Verifying token: {token[:20]}...")
        token_data = verify_token(token)
        print(f"DEBUG: Token verified, username: {token_data.username}")
        user = get_user(username=token_data.username)
        print(f"DEBUG: User lookup result: {user}")
        if user is None:
            print(f"DEBUG: User not found in database")
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="User not found",
                headers={"WWW-Authenticate": "Bearer"},
            )
        print(f"DEBUG: User found: {user.username}")
        return user
    except ValueError as e:
        print(f"DEBUG: Token verification failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except Exception as e:
        print(f"DEBUG: Unexpected error: {e}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )


@router.get("/")
async def root():
    return {"message": "UNO Game Backend"}


@router.get("/health")
async def health_check():
    return {"status": "healthy", "service": "uno-backend"}


# Authentication endpoints
@router.post("/api/auth/signup", response_model=TokenResponse)
async def signup(request: SignupRequest):
    """Register a new user."""
    # Validate username
    if not validate_username(request.username):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Username must be 3-20 characters long"
        )
    
    # Validate PIN
    if not validate_pin(request.pin):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="PIN must be exactly 4 digits"
        )
    
    # Create user
    try:
        print(f"DEBUG: Creating user with username: {request.username}")
        user = create_user(request.username, request.pin)
        print(f"DEBUG: User created successfully: {user.username}")
        print(f"DEBUG: Users in database after creation: {list_usernames()}")
    except HTTPException as e:
        raise e
    
    # Create access token
    access_token = create_access_token(data={"sub": user.username})
    print(f"DEBUG: Token created for user: {user.username}")
    
    return TokenResponse(
        access_token=access_token,
        username=user.username
    )


@router.post("/api/auth/login", response_model=TokenResponse)
async def login(request: LoginRequest):
    """Authenticate user and return token."""
    # Validate PIN format
    if not validate_pin(request.pin):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="PIN must be exactly 4 digits"
        )
    
    # Authenticate user
    user = authenticate_user(request.username, request.pin)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or PIN"
        )
    
    # Create access token
    access_token = create_access_token(data={"sub": user.username})
    
    return TokenResponse(
        access_token=access_token,
        username=user.username
    )


@router.get("/api/auth/me")
async def get_current_user_info(current_user: dict = Depends(get_current_user)):
    """Get current user information."""
    return {
        "username": current_user.username,
        "created_at": current_user.created_at.isoformat()
    }


@router.get("/api/auth/debug")
async def debug_auth():
    """Debug endpoint to check stored users."""
    users = list_usernames()
    return {
        "users": users,
        "user_count": len(users)
    }


@router.post("/api/games/create")
async def create_game(current_user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """Create a new game"""
    game_id = f"game_{len(games) + 1}"
    game = UNOGame(game_id)
    
    # Ensure unique game code
    while game.game_code in games_by_code or get_game_by_code_from_db(db, game.game_code):
        game.game_code = game._generate_game_code()
    
    games[game_id] = game
    games_by_code[game.game_code] = game_id
    
    # Save to database
    save_game(db, game_id)
    
    # Broadcast updated game list to all connected players
    await broadcast_game_list_update()
    
    return {
        "game_id": game_id, 
        "game_code": game.game_code,
        "message": "Game created successfully"
    }


@router.get("/api/games")
async def list_games(current_user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """List all available games"""
    available_games = []
    
    # Get all games from database
    from game_storage import list_games_from_db
    db_games = list_games_from_db(db)
    
    # Process each game (load into cache if not already there)
    for db_game in db_games:
        # Skip ended games
        if db_game.game_state_json:
            import json
            state_dict = json.loads(db_game.game_state_json)
            if state_dict.get("game_ended", False):
                continue
        
        # Load game into cache if not already there
        game = get_game(db, db_game.id)
        if not game:
            continue
            
        available_games.append({
            "game_id": game.game_id,
            "game_code": game.game_code,
            "player_count": len(game.players),
            "max_players": 2,
            "game_started": game.game_started,
            "status": "full" if len(game.players) >= 2 else "waiting" if not game.game_started else "in_progress"
        })
    
    return {"games": available_games}


@router.get("/api/games/code/{game_code}")
async def get_game_by_code(game_code: str, current_user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """Get game information by game code"""
    # Check cache first
    if game_code in games_by_code:
        game_id = games_by_code[game_code]
    else:
        # Check database
        game_id = get_game_by_code_from_db(db, game_code)
        if not game_id:
            raise HTTPException(status_code=404, detail="Game code not found")
        # Load game into cache
        get_game(db, game_id)
    
    game = get_game(db, game_id)
    if not game:
        raise HTTPException(status_code=404, detail="Game not found")
    
    # Check if game has ended
    if game.game_ended:
        raise HTTPException(status_code=410, detail="Game has ended")
    
    # Count disconnected players
    disconnected_count = 0
    if game_id in disconnected_players:
        disconnected_count = len(disconnected_players[game_id])
    
    return {
        "game_id": game_id,
        "game_code": game_code,
        "player_count": len(game.players),
        "max_players": 2,
        "game_started": game.game_started,
        "disconnected_players": disconnected_count,
        "status": "full" if len(game.players) >= 2 else "waiting" if not game.game_started else "in_progress"
    }


@router.get("/api/games/{game_id}")
async def get_game_state(game_id: str, current_user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """Get current game state"""
    game = get_game(db, game_id)
    if not game:
        raise HTTPException(status_code=404, detail="Game not found")
    
    return game.get_game_state()


@router.get("/api/games/{game_id}/my-slot")
async def get_my_slot(game_id: str, current_user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """Get the current user's slot information if they're in the game"""
    game = get_game(db, game_id)
    if not game:
        raise HTTPException(status_code=404, detail="Game not found")
    
    username = current_user.username
    
    # Check if user owns a slot
    if game_id not in game_player_ownership:
        return {"has_slot": False, "message": "You are not in this game"}
    
    slot_index = None
    for slot_idx, slot_username in game_player_ownership[game_id].items():
        if slot_username == username:
            slot_index = slot_idx
            break
    
    if slot_index is None:
        return {"has_slot": False, "message": "You are not in this game"}
    
    # Get player info
    player = game.players[slot_index]
    is_connected = player.id in active_connections
    is_disconnected = game_id in disconnected_players and username in disconnected_players[game_id]
    
    return {
        "has_slot": True,
        "slot_index": slot_index,
        "player_id": player.id,
        "player_name": player.name,
        "is_connected": is_connected,
        "can_rejoin": is_disconnected and not is_connected,
        "message": f"You are player {slot_index + 1} in this game"
    }


@router.post("/api/games/{game_id}/join")
async def join_game(game_id: str, current_user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """Join a game by game ID. Automatically handles both new joins and rejoins."""
    game = get_game(db, game_id)
    if not game:
        raise HTTPException(status_code=404, detail="Game not found")
    
    username = current_user.username
    
    # Initialize game_player_ownership tracking for this game if not exists
    if game_id not in game_player_ownership:
        game_player_ownership[game_id] = {}
    if game_id not in player_identities:
        player_identities[game_id] = {}
    
    # Note: We don't populate ownership from player.name for backward compatibility
    # because player.name is not unique (two users could have the same name).
    # For legacy games, slots remain unowned until someone joins and claims them with their unique username.
    
    # Step 1: Check if this username already owns a slot in this game
    existing_slot_index = None
    for slot_idx, slot_username in game_player_ownership[game_id].items():
        if slot_username == username:
            existing_slot_index = slot_idx
            break
    
    # Step 2: If user owns a slot, rejoin their slot
    if existing_slot_index is not None:
        slot_index = existing_slot_index
        existing_player = game.players[slot_index]
        player_id = existing_player.id
        
        # Check if we have a disconnected player state to restore
        if game_id in disconnected_players and username in disconnected_players[game_id]:
            # Restore from disconnected player state
            disconnected_player = disconnected_players[game_id][username]
            game.players[slot_index] = disconnected_player
            player_id = disconnected_player.id
            del disconnected_players[game_id][username]
            message = f"{username} rejoined the game."
        elif existing_player.id in active_connections:
            # Already connected
            return {
                "player_id": player_id,
                "game_id": game_id,
                "session_token": player_sessions.get(game_id, {}).get(player_id, ""),
                "message": f"{username} is already connected to this game."
            }
        else:
            message = f"{username} rejoined the game."
    
    # Step 3: If user doesn't own a slot, find available slot
    else:
        if len(game.players) < 2:
            slot_index = len(game.players)
            player_id = f"player_{slot_index + 1}"
            from models import Player
            player = Player(id=player_id, name=username, cards=[])
            game.players.append(player)
            message = f"{username} joined the game."
        else:
            available_slot_index = None
            for i, player in enumerate(game.players):
                if player.id not in active_connections:
                    slot_owner = game_player_ownership[game_id].get(i)
                    if slot_owner is None or slot_owner != username:
                        available_slot_index = i
                        break
            
            if available_slot_index is not None:
                slot_index = available_slot_index
                old_player = game.players[slot_index]
                old_player_id = old_player.id
                player_id = f"player_{slot_index + 1}"
                
                from models import Player
                player = Player(id=player_id, name=username, cards=[])
                
                if game.game_started:
                    player.cards = old_player.cards.copy()
                    if slot_index == game.current_player_index:
                        player.is_current_turn = True
                
                game.players[slot_index] = player
                
                old_slot_owner = game_player_ownership[game_id].get(slot_index)
                if old_slot_owner and game_id in disconnected_players and old_slot_owner in disconnected_players[game_id]:
                    del disconnected_players[game_id][old_slot_owner]
                
                if old_player_id in active_connections:
                    del active_connections[old_player_id]
                
                message = f"{username} joined the game."
            else:
                raise HTTPException(status_code=400, detail="Game is full and all slots are occupied")
    
    # Update username-based slot ownership
    game_player_ownership[game_id][slot_index] = username
    player_identities[game_id][player_id] = player_id
    
    # Broadcast updated game list
    await broadcast_game_list_update()
    
    # Generate session token
    session_token = secrets.token_urlsafe(32)
    if game_id not in player_sessions:
        player_sessions[game_id] = {}
    player_sessions[game_id][player_id] = session_token
    
    save_game(db, game_id)
    
    if game.game_started:
        await broadcast_game_state(game_id, {
            "type": "player_joined" if "joined" in message.lower() else "player_rejoined",
            "message": message,
            "player": game.players[slot_index].model_dump()
        })
    
    return {
        "player_id": player_id, 
        "game_id": game_id, 
        "session_token": session_token,
        "message": message
    }


@router.post("/api/games/join-by-code")
async def join_game_by_code(request: JoinGameByCodeRequest, current_user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """Join a game by 5-character game code. Automatically handles both new joins and rejoins."""
    game_code = request.game_code
    username = current_user.username
    
    # Check cache first
    if game_code in games_by_code:
        game_id = games_by_code[game_code]
    else:
        # Check database
        game_id = get_game_by_code_from_db(db, game_code)
        if not game_id:
            raise HTTPException(status_code=404, detail="Game code not found")
        # Load game into cache
        get_game(db, game_id)
    
    game = get_game(db, game_id)
    if not game:
        raise HTTPException(status_code=404, detail="Game not found")
    
    # Initialize game_player_ownership tracking for this game if not exists
    if game_id not in game_player_ownership:
        game_player_ownership[game_id] = {}
    if game_id not in player_identities:
        player_identities[game_id] = {}
    
    # Note: We don't populate ownership from player.name for backward compatibility
    # because player.name is not unique (two users could have the same name).
    # For legacy games, slots remain unowned until someone joins and claims them with their unique username.
    
    # Step 1: Check if this username already owns a slot in this game
    existing_slot_index = None
    for slot_idx, slot_username in game_player_ownership[game_id].items():
        if slot_username == username:
            existing_slot_index = slot_idx
            break
    
    # Step 2: If user owns a slot, rejoin their slot
    if existing_slot_index is not None:
        slot_index = existing_slot_index
        existing_player = game.players[slot_index]
        player_id = existing_player.id
        
        # Check if we have a disconnected player state to restore
        if game_id in disconnected_players and username in disconnected_players[game_id]:
            # Restore from disconnected player state
            disconnected_player = disconnected_players[game_id][username]
            # Update the player in place, preserving slot position
            game.players[slot_index] = disconnected_player
            player_id = disconnected_player.id
            # Remove from disconnected players
            del disconnected_players[game_id][username]
            message = f"{username} rejoined the game."
        elif existing_player.id in active_connections:
            # Already connected, just return existing slot
            return {
                "player_id": player_id,
                "game_id": game_id,
                "session_token": player_sessions.get(game_id, {}).get(player_id, ""),
                "message": f"{username} is already connected to this game."
            }
        else:
            # Slot exists but player is not connected, restore the existing player
            message = f"{username} rejoined the game."
    
    # Step 3: If user doesn't own a slot, find available slot (empty or disconnected from different user)
    else:
        available_slot_index = None
        
        # Check for empty slots first
        if len(game.players) < 2:
            # Create new slot
            slot_index = len(game.players)
            player_id = f"player_{slot_index + 1}"
            from models import Player
            player = Player(id=player_id, name=username, cards=[])
            game.players.append(player)
            message = f"{username} joined the game."
        
        # Check for disconnected slots from different users
        elif len(game.players) >= 2:
            for i, player in enumerate(game.players):
                if player.id not in active_connections:
                    # Check if this slot belongs to a different user (or no user)
                    slot_owner = game_player_ownership[game_id].get(i)
                    if slot_owner is None or slot_owner != username:
                        # This slot is available (either no owner or belongs to disconnected different user)
                        available_slot_index = i
                        break
            
            if available_slot_index is not None:
                slot_index = available_slot_index
                old_player = game.players[slot_index]
                old_player_id = old_player.id
                player_id = f"player_{slot_index + 1}"
                
                from models import Player
                player = Player(id=player_id, name=username, cards=[])
                
                # If game was started, give the new player the same cards as the old player
                if game.game_started:
                    player.cards = old_player.cards.copy()
                    # Reset turn if it was the disconnected player's turn
                    if slot_index == game.current_player_index:
                        player.is_current_turn = True
                
                game.players[slot_index] = player
                
                # Clean up old player's disconnected state if it exists
                old_slot_owner = game_player_ownership[game_id].get(slot_index)
                if old_slot_owner and game_id in disconnected_players and old_slot_owner in disconnected_players[game_id]:
                    del disconnected_players[game_id][old_slot_owner]
                
                # Remove old player from active connections
                if old_player_id in active_connections:
                    del active_connections[old_player_id]
                
                message = f"{username} joined the game."
            else:
                raise HTTPException(status_code=400, detail="Game is full and all slots are occupied")
    
    # Update username-based slot ownership
    game_player_ownership[game_id][slot_index] = username
    
    # Track player identities for backward compatibility
    player_identities[game_id][player_id] = player_id
    
    # Broadcast updated game list to all connected players
    await broadcast_game_list_update()
    
    # Generate session token for this player
    session_token = secrets.token_urlsafe(32)
    if game_id not in player_sessions:
        player_sessions[game_id] = {}
    player_sessions[game_id][player_id] = session_token
    
    # Save game state to database
    save_game(db, game_id)
    
    # Broadcast updated game state
    if game.game_started:
        await broadcast_game_state(game_id, {
            "type": "player_joined" if "joined" in message.lower() else "player_rejoined",
            "message": message,
            "player": game.players[slot_index].model_dump()
        })
    
    return {
        "player_id": player_id, 
        "game_id": game_id, 
        "session_token": session_token,
        "message": message
    }


@router.get("/api/games/{game_id}/can-rejoin/{player_id}")
async def can_rejoin_game(game_id: str, player_id: str, current_user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """Check if a player can rejoin a game by player_id"""
    game = get_game(db, game_id)
    if not game:
        raise HTTPException(status_code=404, detail="Game not found")
    
    # Check if there's a disconnected player with this player_id
    if game_id in disconnected_players and player_id in disconnected_players[game_id]:
        player = disconnected_players[game_id][player_id]
        # Check if their slot is available
        for i, current_player in enumerate(game.players):
            if current_player.id == player_id and current_player.id not in active_connections:
                return {
                    "can_rejoin": True,
                    "player_id": player_id,
                    "slot_index": i,
                    "message": f"Found disconnected player '{player.name}' with available slot"
                }
    
    return {"can_rejoin": False, "message": "No disconnected player found with this player_id or slot not available"}


@router.post("/api/games/{game_id}/rejoin/{player_id}")
async def rejoin_game(game_id: str, player_id: str, current_user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """Rejoin a game by player_id (for disconnected players)"""
    game = get_game(db, game_id)
    if not game:
        raise HTTPException(status_code=404, detail="Game not found")
    
    # Check if there's a disconnected player with this player_id
    if game_id not in disconnected_players:
        raise HTTPException(status_code=400, detail="No disconnected players found in this game")
    
    if player_id not in disconnected_players[game_id]:
        raise HTTPException(status_code=400, detail=f"No disconnected player found with player_id '{player_id}'")
    
    disconnected_player = disconnected_players[game_id][player_id]
    
    # Check if their slot is available
    slot_available = False
    slot_index = None
    for i, current_player in enumerate(game.players):
        if current_player.id == player_id and current_player.id not in active_connections:
            slot_available = True
            slot_index = i
            break
    
    if not slot_available:
        raise HTTPException(status_code=400, detail="Your slot is not available for rejoining")
    
    # Restore the player to their slot
    game.players[slot_index] = disconnected_player
    
    # Remove from disconnected players
    del disconnected_players[game_id][player_id]
    
    # Save game state to database
    save_game(db, game_id)
    
    # Broadcast the reconnection
    await broadcast_game_state(game_id, {
        "type": "player_rejoined",
        "message": f"{disconnected_player.name} reconnected to the game",
        "rejoined_player": disconnected_player.model_dump()
    })
    
    # Broadcast updated game list
    await broadcast_game_list_update()
    
    return {
        "player_id": player_id, 
        "message": f"Successfully reconnected {disconnected_player.name} to their original slot"
    }


@router.get("/api/games/{game_id}/session/{player_id}")
async def check_player_session(game_id: str, player_id: str, current_user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """Check if a player has an active session in this game by player_id"""
    game = get_game(db, game_id)
    if not game:
        raise HTTPException(status_code=404, detail="Game not found")
    
    # Check if player has an active session
    has_session = False
    can_rejoin = False
    message = "No active session found"
    
    if game_id in player_sessions and player_id in player_sessions[game_id]:
        has_session = True
        
        # Check if they can rejoin (either disconnected or active)
        if game_id in disconnected_players and player_id in disconnected_players[game_id]:
            can_rejoin = True
            player = disconnected_players[game_id][player_id]
            message = f"Found active session for '{player.name}' - can rejoin"
        elif player_id in active_connections:
            # Check if they're currently active in the game
            for player in game.players:
                if player.id == player_id:
                    can_rejoin = True
                    message = f"Found active session for '{player.name}' - already connected"
                    break
    
    return {
        "has_session": has_session,
        "can_rejoin": can_rejoin,
        "message": message
    }


@router.post("/api/games/{game_id}/start")
async def start_game(game_id: str, current_user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """Start the game"""
    game = get_game(db, game_id)
    if not game:
        raise HTTPException(status_code=404, detail="Game not found")
    
    if len(game.players) != 2:
        raise HTTPException(status_code=400, detail="Need exactly 2 players to start")
    
    game.start_game()
    save_game(db, game_id)
    return {"message": "Game started successfully"}


@router.post("/api/games/{game_id}/play")
async def play_card(game_id: str, request: PlayCardRequest, current_user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """Play a card"""
    game = get_game(db, game_id)
    if not game:
        raise HTTPException(status_code=404, detail="Game not found")
    
    player_index = next((i for i, p in enumerate(game.players) if p.id == request.player_id), None)
    
    if player_index is None:
        raise HTTPException(status_code=404, detail="Player not found")
    
    try:
        result = game.play_card(player_index, request.card_index, request.new_color)
        save_game(db, game_id)
        return result
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/api/games/{game_id}/draw")
async def draw_card(game_id: str, request: DrawCardRequest, current_user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """Draw a card"""
    game = get_game(db, game_id)
    if not game:
        raise HTTPException(status_code=404, detail="Game not found")
    
    player_index = next((i for i, p in enumerate(game.players) if p.id == request.player_id), None)
    
    if player_index is None:
        raise HTTPException(status_code=404, detail="Player not found")
    
    card = game.draw_card(player_index)
    if card:
        # Move to next player after drawing
        game._next_player()
        save_game(db, game_id)
        return {"card": card, "next_player": game.current_player_index}
    else:
        raise HTTPException(status_code=400, detail="Cannot draw card")


@router.post("/api/games/{game_id}/reclaim-slot")
async def reclaim_slot(game_id: str, request: ReclaimSlotRequest, current_user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """Allow original player to reclaim their slot"""
    game = get_game(db, game_id)
    if not game:
        raise HTTPException(status_code=404, detail="Game not found")
    
    # Check if we have the disconnected player stored
    if game_id not in disconnected_players or request.original_player_id not in disconnected_players[game_id]:
        raise HTTPException(status_code=400, detail="No disconnected player found to restore")
    
    # Find the slot that belongs to the original player
    target_slot = None
    for i, player in enumerate(game.players):
        if player.id == request.original_player_id:
            target_slot = i
            break
    
    if target_slot is None:
        raise HTTPException(status_code=404, detail="No slot found for this player")
    
    # Check if the slot is currently occupied by an active player
    current_occupant = game.players[target_slot]
    if current_occupant.id in active_connections:
        raise HTTPException(status_code=400, detail="Slot is currently occupied by an active player")
    
    # Restore the original player with their original cards and state
    original_player = disconnected_players[game_id][request.original_player_id]
    
    # Update the player's name if it changed
    original_player.name = request.player_name
    
    # Restore the original player to their slot
    game.players[target_slot] = original_player
    
    # Remove from disconnected players
    del disconnected_players[game_id][request.original_player_id]
    
    # Save game state to database
    save_game(db, game_id)
    
    # Broadcast the reclamation
    await broadcast_game_state(game_id, {
        "type": "player_reclaimed_slot",
        "message": f"{request.player_name} reconnected to the game",
        "reclaimed_player": original_player.model_dump()
    })
    
    return {"player_id": original_player.id, "message": f"Successfully restored {request.player_name} to their original slot"}


@router.get("/api/games/{game_id}/can-reclaim/{original_player_id}")
async def can_reclaim_slot(game_id: str, original_player_id: str, current_user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """Check if a player can reclaim their slot"""
    game = get_game(db, game_id)
    if not game:
        raise HTTPException(status_code=404, detail="Game not found")
    
    # Check if we have the disconnected player stored
    if game_id not in disconnected_players or original_player_id not in disconnected_players[game_id]:
        return {"can_reclaim": False, "reason": "No disconnected player found to restore"}
    
    # Check if the player's original slot is available
    for i, player in enumerate(game.players):
        if player.id == original_player_id:
            # Found the player's slot, check if it's available
            if player.id not in active_connections:
                return {
                    "can_reclaim": True, 
                    "slot_index": i,
                    "reason": "Original slot is available for restoration"
                }
            else:
                return {"can_reclaim": False, "reason": "Original slot is currently occupied by an active player"}
    
    return {"can_reclaim": False, "reason": "Original slot not found"}


@router.delete("/api/games/{game_id}")
async def delete_game(game_id: str, current_user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """Delete a game"""
    game = get_game(db, game_id)
    if not game:
        raise HTTPException(status_code=404, detail="Game not found")
    
    game_code = game.game_code
    
    # Remove from database
    from game_storage import delete_game_from_db
    delete_game_from_db(db, game_id)
    
    # Remove game from dictionaries
    if game_id in games:
        del games[game_id]
    if game_code in games_by_code:
        del games_by_code[game_code]
    
    # Clean up related data
    cleanup_game_data(game_id)
    
    # Clean up player sessions for this game
    if game_id in player_sessions:
        del player_sessions[game_id]
    
    # Remove active connections for players in this game
    for player in game.players:
        if player.id in active_connections:
            try:
                await active_connections[player.id].close()
            except Exception:
                pass
            del active_connections[player.id]
    
    # Broadcast updated game list to all connected players
    await broadcast_game_list_update()
    
    return {
        "message": f"Game {game_id} (code: {game_code}) deleted successfully",
        "game_id": game_id,
        "game_code": game_code
    }
