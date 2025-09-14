import json
from fastapi import WebSocket, WebSocketDisconnect
from models import CardColor
from utils import games, active_connections, disconnected_players, broadcast_game_state, broadcast_game_list_update


async def lobby_websocket_endpoint(websocket: WebSocket, player_id: str):
    """WebSocket endpoint for lobby updates (game list)"""
    await websocket.accept()
    active_connections[player_id] = websocket
    
    # Send initial game list
    await send_game_list_to_player(websocket)
    
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


async def game_websocket_endpoint(websocket: WebSocket, game_id: str, player_id: str):
    """WebSocket endpoint for real-time game updates"""
    await websocket.accept()
    print(f"WebSocket connection accepted for game {game_id}, player {player_id}")
    
    # Store the connection
    active_connections[player_id] = websocket
    
    # Send initial game state to the newly connected player
    if game_id in games:
        game = games[game_id]
        game_state = game.get_game_state()
        print(f"Sending initial game state to player {player_id}")
        await websocket.send_text(json.dumps({
            "type": "game_update",
            "game_state": game_state.model_dump(),  # Use model_dump() for Pydantic v2
        }))
    else:
        print(f"Game {game_id} not found for player {player_id}")
        await websocket.send_text(json.dumps({
            "type": "error",
            "message": "Game not found"
        }))
        return
    
    try:
        while True:
            # Handle incoming messages
            data = await websocket.receive_text()
            message = json.loads(data)
            print(f"Received WebSocket message from {player_id}: {message}")
            
            # Handle different message types
            if message.get("type") == "ping":
                print(f"Sending pong to {player_id}")
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
                            await broadcast_game_state(game_id, {
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
                        await broadcast_game_state(game_id)
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
                    
            elif message.get("type") == "join_game":
                # Handle player joining the game via WebSocket
                if game_id in games:
                    game = games[game_id]
                    # Verify this player is actually in the game
                    player_in_game = next((p for p in game.players if p.id == player_id), None)
                    if player_in_game:
                        print(f"Player {player_id} joined game {game_id} via WebSocket")
                        # Send confirmation that they're properly connected
                        await websocket.send_text(json.dumps({
                            "type": "join_confirmed",
                            "message": f"Successfully joined game {game_id}",
                            "player_id": player_id
                        }))
                        
                        # Broadcast updated game state to all players
                        await broadcast_game_state(game_id)
                    else:
                        await websocket.send_text(json.dumps({
                            "type": "error",
                            "message": "Player not found in game"
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
                            await broadcast_game_state(game_id, {
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
            
            # Find the disconnected player and store their information
            player = next((p for p in game.players if p.id == player_id), None)
            if player:
                # Store the disconnected player for potential restoration
                if game_id not in disconnected_players:
                    disconnected_players[game_id] = {}
                disconnected_players[game_id][player_id] = player
                
                # Mark the player as disconnected in the game state
                # but keep them in the players list for proper slot management
                
                # Broadcast updated game list to show available slots
                await broadcast_game_list_update()
                
                # If game was started and player disconnected, notify other players
                if game.game_started:
                    await broadcast_game_state(game_id, {
                        "type": "player_disconnected",
                        "message": f"{player.name} disconnected from the game",
                        "disconnected_player_id": player_id,
                        "can_rejoin": True
                    })
                    
                # Also send a message to the lobby to update game status
                await broadcast_game_list_update()


async def send_game_list_to_player(websocket: WebSocket):
    """Send current game list to a specific player"""
    from utils import send_game_list_to_player as _send_game_list_to_player
    await _send_game_list_to_player(websocket)
