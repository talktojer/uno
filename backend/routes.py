from fastapi import APIRouter, HTTPException, Depends, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from typing import Dict
import secrets
from models import JoinGameRequest, JoinGameByCodeRequest, PlayCardRequest, DrawCardRequest, ReclaimSlotRequest, LoginRequest, SignupRequest, TokenResponse
from game_logic import UNOGame
from utils import games, games_by_code, active_connections, player_identities, disconnected_players, player_sessions, broadcast_game_list_update, broadcast_game_state
from auth import authenticate_user, create_user, create_access_token, verify_token, get_user, validate_pin, validate_username

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
        
        # Debug: Check if user is in database
        from auth import get_users_db
        db = get_users_db()
        print(f"DEBUG: Users in database after creation: {list(db.keys())}")
        
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
    from auth import get_users_db
    db = get_users_db()
    return {
        "users": list(db.keys()),
        "user_count": len(db)
    }


@router.post("/api/games/create")
async def create_game(current_user: dict = Depends(get_current_user)):
    """Create a new game"""
    game_id = f"game_{len(games) + 1}"
    game = UNOGame(game_id)
    
    # Ensure unique game code
    while game.game_code in games_by_code:
        game.game_code = game._generate_game_code()
    
    games[game_id] = game
    games_by_code[game.game_code] = game_id
    
    # Broadcast updated game list to all connected players
    await broadcast_game_list_update()
    
    return {
        "game_id": game_id, 
        "game_code": game.game_code,
        "message": "Game created successfully"
    }


@router.get("/api/games")
async def list_games(current_user: dict = Depends(get_current_user)):
    """List all available games"""
    available_games = []
    for game_id, game in games.items():
        # Skip ended games
        if game.game_ended:
            continue
            
        available_games.append({
            "game_id": game_id,
            "game_code": game.game_code,
            "player_count": len(game.players),
            "max_players": 2,
            "game_started": game.game_started,
            "status": "full" if len(game.players) >= 2 else "waiting" if not game.game_started else "in_progress"
        })
    return {"games": available_games}


@router.get("/api/games/code/{game_code}")
async def get_game_by_code(game_code: str, current_user: dict = Depends(get_current_user)):
    """Get game information by game code"""
    if game_code not in games_by_code:
        raise HTTPException(status_code=404, detail="Game code not found")
    
    game_id = games_by_code[game_code]
    game = games[game_id]
    
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
async def get_game_state(game_id: str, current_user: dict = Depends(get_current_user)):
    """Get current game state"""
    if game_id not in games:
        raise HTTPException(status_code=404, detail="Game not found")
    
    return games[game_id].get_game_state()


@router.post("/api/games/{game_id}/join")
async def join_game(game_id: str, current_user: dict = Depends(get_current_user)):
    """Join a game by game ID"""
    if game_id not in games:
        raise HTTPException(status_code=404, detail="Game not found")
    
    game = games[game_id]
    
    # Initialize player identities tracking for this game if not exists
    if game_id not in player_identities:
        player_identities[game_id] = {}
    
    # Check if there's an available slot (either empty or disconnected player)
    available_slots = []
    for i, player in enumerate(game.players):
        if player.id not in active_connections:
            available_slots.append(i)
    
    if len(game.players) >= 2 and not available_slots:
        raise HTTPException(status_code=400, detail="Game is full")
    
    if game.game_started and not available_slots:
        raise HTTPException(status_code=400, detail="Game already started and full")
    
    # If there's an available slot, check if we can claim it
    if available_slots:
        slot_index = available_slots[0]
        old_player_id = game.players[slot_index].id
        
        # Check if this is a disconnected player that can be restored
        if game_id in disconnected_players and old_player_id in disconnected_players[game_id]:
            # This is a disconnected player, we should restore them instead of replacing
            raise HTTPException(status_code=400, detail="This slot belongs to a disconnected player. Please use the reconnect feature instead.")
        
        # Create new player with the same slot
        player_id = f"player_{slot_index + 1}"
        from models import Player
        player = Player(id=player_id, name=current_user.username, cards=[])
        
        # If game was started, give the new player the same cards as the old player
        if game.game_started:
            player.cards = game.players[slot_index].cards.copy()
            # Reset turn if it was the disconnected player's turn
            if slot_index == game.current_player_index:
                player.is_current_turn = True
        
        # Update player identities to track this new player
        player_identities[game_id][player_id] = old_player_id  # New player inherits the slot
        
        game.players[slot_index] = player
        
        # Remove old player from active connections
        if old_player_id in active_connections:
            del active_connections[old_player_id]
        
        message = f"Replaced disconnected player. {current_user.username} joined the game."
    else:
        # Create new player in new slot
        player_id = f"player_{len(game.players) + 1}"
        from models import Player
        player = Player(id=player_id, name=current_user.username, cards=[])
        game.players.append(player)
        
        # Track this player's original slot ownership
        player_identities[game_id][player_id] = player_id
        
        message = f"{current_user.username} joined the game."
    
    # Broadcast updated game list to all connected players
    await broadcast_game_list_update()
    
    # Generate session token for this player
    session_token = secrets.token_urlsafe(32)
    if game_id not in player_sessions:
        player_sessions[game_id] = {}
    player_sessions[game_id][current_user.username] = session_token
    
    # If this is a replacement in a started game, broadcast the updated game state
    if game.game_started:
        await broadcast_game_state(game_id, {
            "type": "player_replaced",
            "message": message,
            "new_player": player.model_dump()
        })
    
    return {
        "player_id": player_id, 
        "game_id": game_id, 
        "session_token": session_token,
        "message": message
    }


@router.post("/api/games/join-by-code")
async def join_game_by_code(request: JoinGameByCodeRequest, current_user: dict = Depends(get_current_user)):
    """Join a game by 5-character game code"""
    game_code = request.game_code
    player_name = current_user.username
    
    if game_code not in games_by_code:
        raise HTTPException(status_code=404, detail="Game code not found")
    
    game_id = games_by_code[game_code]
    game = games[game_id]
    
    # Initialize player identities tracking for this game if not exists
    if game_id not in player_identities:
        player_identities[game_id] = {}
    
    # Check if there's an available slot (either empty or disconnected player)
    available_slots = []
    for i, player in enumerate(game.players):
        if player.id not in active_connections:
            available_slots.append(i)
    
    if len(game.players) >= 2 and not available_slots:
        raise HTTPException(status_code=400, detail="Game is full")
    
    if game.game_started and not available_slots:
        raise HTTPException(status_code=400, detail="Game already started and full")
    
    # If there's an available slot, check if we can claim it
    if available_slots:
        slot_index = available_slots[0]
        old_player_id = game.players[slot_index].id
        
        # Check if this is a disconnected player that can be restored
        if game_id in disconnected_players and old_player_id in disconnected_players[game_id]:
            # This is a disconnected player, we should restore them instead of replacing
            raise HTTPException(status_code=400, detail="This slot belongs to a disconnected player. Please use the reconnect feature instead.")
        
        # Create new player with the same slot
        player_id = f"player_{slot_index + 1}"
        from models import Player
        player = Player(id=player_id, name=player_name, cards=[])
        
        # If game was started, give the new player the same cards as the old player
        if game.game_started:
            player.cards = game.players[slot_index].cards.copy()
            # Reset turn if it was the disconnected player's turn
            if slot_index == game.current_player_index:
                player.is_current_turn = True
        
        # Update player identities to track this new player
        player_identities[game_id][player_id] = old_player_id  # New player inherits the slot
        
        game.players[slot_index] = player
        
        # Remove old player from active connections
        if old_player_id in active_connections:
            del active_connections[old_player_id]
        
        message = f"Replaced disconnected player. {player_name} joined the game."
    else:
        # Create new player in new slot
        player_id = f"player_{len(game.players) + 1}"
        from models import Player
        player = Player(id=player_id, name=player_name, cards=[])
        game.players.append(player)
        
        # Track this player's original slot ownership
        player_identities[game_id][player_id] = player_id
        
        message = f"{player_name} joined the game."
    
    # Broadcast updated game list to all connected players
    await broadcast_game_list_update()
    
    # Generate session token for this player
    session_token = secrets.token_urlsafe(32)
    if game_id not in player_sessions:
        player_sessions[game_id] = {}
    player_sessions[game_id][player_name] = session_token
    
    # If this is a replacement in a started game, broadcast the updated game state
    if game.game_started:
        await broadcast_game_state(game_id, {
            "type": "player_replaced",
            "message": message,
            "new_player": player.model_dump()
        })
    
    return {
        "player_id": player_id, 
        "game_id": game_id, 
        "session_token": session_token,
        "message": message
    }


@router.get("/api/games/{game_id}/can-rejoin/{player_name}")
async def can_rejoin_game(game_id: str, player_name: str, current_user: dict = Depends(get_current_user)):
    """Check if a player can rejoin a game by name"""
    if game_id not in games:
        raise HTTPException(status_code=404, detail="Game not found")
    
    game = games[game_id]
    
    # Check if there's a disconnected player with this name
    if game_id in disconnected_players:
        for player_id, player in disconnected_players[game_id].items():
            if player.name == player_name:
                # Check if their slot is available
                for i, current_player in enumerate(game.players):
                    if current_player.id == player_id and current_player.id not in active_connections:
                        return {
                            "can_rejoin": True,
                            "player_id": player_id,
                            "slot_index": i,
                            "message": f"Found disconnected player '{player_name}' with available slot"
                        }
    
    return {"can_rejoin": False, "message": "No disconnected player found with this name or slot not available"}


@router.post("/api/games/{game_id}/rejoin")
async def rejoin_game(game_id: str, current_user: dict = Depends(get_current_user)):
    """Rejoin a game by player name (for disconnected players)"""
    if game_id not in games:
        raise HTTPException(status_code=404, detail="Game not found")
    
    game = games[game_id]
    player_name = current_user.username
    
    # Check if there's a disconnected player with this name
    if game_id not in disconnected_players:
        raise HTTPException(status_code=400, detail="No disconnected players found in this game")
    
    # Find the disconnected player
    disconnected_player_id = None
    disconnected_player = None
    for player_id, player in disconnected_players[game_id].items():
        if player.name == player_name:
            disconnected_player_id = player_id
            disconnected_player = player
            break
    
    if not disconnected_player:
        raise HTTPException(status_code=400, detail=f"No disconnected player found with name '{player_name}'")
    
    # Check if their slot is available
    slot_available = False
    slot_index = None
    for i, current_player in enumerate(game.players):
        if current_player.id == disconnected_player_id and current_player.id not in active_connections:
            slot_available = True
            slot_index = i
            break
    
    if not slot_available:
        raise HTTPException(status_code=400, detail="Your slot is not available for rejoining")
    
    # Restore the player to their slot
    game.players[slot_index] = disconnected_player
    
    # Remove from disconnected players
    del disconnected_players[game_id][disconnected_player_id]
    
    # Broadcast the reconnection
    await broadcast_game_state(game_id, {
        "type": "player_rejoined",
        "message": f"{player_name} reconnected to the game",
        "rejoined_player": disconnected_player.model_dump()
    })
    
    # Broadcast updated game list
    await broadcast_game_list_update()
    
    return {
        "player_id": disconnected_player_id, 
        "message": f"Successfully reconnected {player_name} to their original slot"
    }


@router.get("/api/games/{game_id}/session/{player_name}")
async def check_player_session(game_id: str, player_name: str, current_user: dict = Depends(get_current_user)):
    """Check if a player has an active session in this game"""
    if game_id not in games:
        raise HTTPException(status_code=404, detail="Game not found")
    
    # Check if player has an active session
    has_session = False
    can_rejoin = False
    message = "No active session found"
    
    if game_id in player_sessions and player_name in player_sessions[game_id]:
        has_session = True
        
        # Check if they can rejoin (either disconnected or active)
        if game_id in disconnected_players:
            for player_id, player in disconnected_players[game_id].items():
                if player.name == player_name:
                    can_rejoin = True
                    message = f"Found active session for '{player_name}' - can rejoin"
                    break
        
        if not can_rejoin:
            # Check if they're currently active in the game
            for player in games[game_id].players:
                if player.name == player_name and player.id in active_connections:
                    can_rejoin = True
                    message = f"Found active session for '{player_name}' - already connected"
                    break
    
    return {
        "has_session": has_session,
        "can_rejoin": can_rejoin,
        "message": message
    }


@router.post("/api/games/{game_id}/start")
async def start_game(game_id: str, current_user: dict = Depends(get_current_user)):
    """Start the game"""
    if game_id not in games:
        raise HTTPException(status_code=404, detail="Game not found")
    
    game = games[game_id]
    if len(game.players) != 2:
        raise HTTPException(status_code=400, detail="Need exactly 2 players to start")
    
    game.start_game()
    return {"message": "Game started successfully"}


@router.post("/api/games/{game_id}/play")
async def play_card(game_id: str, request: PlayCardRequest, current_user: dict = Depends(get_current_user)):
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


@router.post("/api/games/{game_id}/draw")
async def draw_card(game_id: str, request: DrawCardRequest, current_user: dict = Depends(get_current_user)):
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


@router.post("/api/games/{game_id}/reclaim-slot")
async def reclaim_slot(game_id: str, request: ReclaimSlotRequest, current_user: dict = Depends(get_current_user)):
    """Allow original player to reclaim their slot"""
    if game_id not in games:
        raise HTTPException(status_code=404, detail="Game not found")
    
    game = games[game_id]
    
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
    
    # Broadcast the reclamation
    await broadcast_game_state(game_id, {
        "type": "player_reclaimed_slot",
        "message": f"{request.player_name} reconnected to the game",
        "reclaimed_player": original_player.model_dump()
    })
    
    return {"player_id": original_player.id, "message": f"Successfully restored {request.player_name} to their original slot"}


@router.get("/api/games/{game_id}/can-reclaim/{original_player_id}")
async def can_reclaim_slot(game_id: str, original_player_id: str, current_user: dict = Depends(get_current_user)):
    """Check if a player can reclaim their slot"""
    if game_id not in games:
        raise HTTPException(status_code=404, detail="Game not found")
    
    # Check if we have the disconnected player stored
    if game_id not in disconnected_players or original_player_id not in disconnected_players[game_id]:
        return {"can_reclaim": False, "reason": "No disconnected player found to restore"}
    
    # Check if the player's original slot is available
    for i, player in enumerate(games[game_id].players):
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
