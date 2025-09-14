import json
from typing import Dict
from fastapi import WebSocket
from models import Player


# Global state management
games: Dict[str, 'UNOGame'] = {}
games_by_code: Dict[str, str] = {}  # Maps game codes to game IDs
active_connections: Dict[str, WebSocket] = {}
# Track original player ownership to prevent slot stealing
player_identities: Dict[str, Dict[str, str]] = {}  # game_id -> {player_id -> original_slot_owner}
# Track disconnected players for proper restoration
disconnected_players: Dict[str, Dict[str, Player]] = {}  # game_id -> {player_id -> Player}
# Track player sessions for rejoining
player_sessions: Dict[str, Dict[str, str]] = {}  # game_id -> {player_name -> session_token}


async def broadcast_game_state(game_id: str, additional_data: dict = None):
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


async def send_game_list_to_player(websocket: WebSocket):
    """Send current game list to a specific player"""
    available_games = []
    for game_id, game in games.items():
        # Count active (connected) players
        active_players = sum(1 for p in game.players if p.id in active_connections)
        
        # Check for disconnected players
        disconnected_count = 0
        if game_id in disconnected_players:
            disconnected_count = len(disconnected_players[game_id])
        
        # Determine game status
        if len(game.players) >= 2 and active_players >= 2:
            status = "full"
        elif game.game_started and active_players < 2:
            if disconnected_count > 0:
                status = "waiting_for_rejoin"
            else:
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
            "disconnected_players": disconnected_count,
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


async def broadcast_game_list_update():
    """Broadcast updated game list to all connected players"""
    available_games = []
    for game_id, game in games.items():
        # Count active (connected) players
        active_players = sum(1 for p in game.players if p.id in active_connections)
        
        # Check for disconnected players
        disconnected_count = 0
        if game_id in disconnected_players:
            disconnected_count = len(disconnected_players[game_id])
        
        # Determine game status
        if len(game.players) >= 2 and active_players >= 2:
            status = "full"
        elif game.game_started and active_players < 2:
            if disconnected_count > 0:
                status = "waiting_for_rejoin"
            else:
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
            "disconnected_players": disconnected_count,
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


def cleanup_game_data(game_id: str):
    """Clean up game data when a game is removed"""
    if game_id in player_identities:
        del player_identities[game_id]
    if game_id in disconnected_players:
        del disconnected_players[game_id]
