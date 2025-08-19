#!/usr/bin/env python3
"""
Test script to verify that the duplicate player bug is fixed.
This simulates the scenario where Kiki disconnects and reconnects,
which was causing "Kiki vs Kiki" duplicate player issues.
"""

import asyncio
import json
import websockets
import requests
import time

# Test configuration
API_BASE = "http://localhost:8000"
WS_BASE = "ws://localhost:8000"

async def test_duplicate_player_fix():
    """Test that the duplicate player bug is fixed"""
    
    print("🧪 Testing Duplicate Player Fix...")
    
    # Step 1: Create a game
    print("1. Creating a new game...")
    response = requests.post(f"{API_BASE}/api/games/create")
    if response.status_code != 200:
        print(f"❌ Failed to create game: {response.status_code}")
        return
    
    game_data = json.loads(response.body)
    game_id = game_data['game_id']
    game_code = game_data['game_code']
    print(f"✅ Game created: {game_code}")
    
    # Step 2: Kiki joins the game
    print("2. Kiki joining the game...")
    response = requests.post(
        f"{API_BASE}/api/games/join-by-code",
        json={"game_code": game_code, "player_name": "Kiki"}
    )
    if response.status_code != 200:
        print(f"❌ Failed to join game: {response.status_code}")
        return
    
    kiki_data = json.loads(response.body)
    kiki_player_id = kiki_data['player_id']
    print(f"✅ Kiki joined: {kiki_player_id}")
    
    # Step 3: Alice joins the game
    print("3. Alice joining the game...")
    response = requests.post(
        f"{API_BASE}/api/games/join-by-code",
        json={"game_code": game_code, "player_name": "Alice"}
    )
    if response.status_code != 200:
        print(f"❌ Failed to join game: {response.status_code}")
        return
    
    alice_data = json.loads(response.body)
    alice_player_id = alice_data['player_id']
    print(f"✅ Alice joined: {alice_player_id}")
    
    # Step 4: Start the game
    print("4. Starting the game...")
    response = requests.post(f"{API_BASE}/api/games/{game_id}/start")
    if response.status_code != 200:
        print(f"❌ Failed to start game: {response.status_code}")
        return
    
    print("✅ Game started")
    
    # Step 5: Simulate Kiki disconnecting (by closing WebSocket)
    print("5. Simulating Kiki disconnection...")
    
    # Connect Kiki's WebSocket
    kiki_ws_url = f"{WS_BASE}/ws/{game_id}/{kiki_player_id}"
    async with websockets.connect(kiki_ws_url) as kiki_ws:
        # Send a ping to establish connection
        await kiki_ws.send(json.dumps({"type": "ping"}))
        time.sleep(1)  # Give time for connection to be established
        
        # Now close the connection to simulate disconnection
        await kiki_ws.close()
    
    print("✅ Kiki disconnected")
    time.sleep(2)  # Give time for backend to process disconnection
    
    # Step 6: Check if Kiki can reclaim her slot
    print("6. Checking if Kiki can reclaim her slot...")
    response = requests.get(f"{API_BASE}/api/games/{game_id}/can-reclaim/{kiki_player_id}")
    if response.status_code != 200:
        print(f"❌ Failed to check slot reclamation: {response.status_code}")
        return
    
    can_reclaim_data = json.loads(response.body)
    print(f"✅ Can reclaim: {can_reclaim_data}")
    
    if not can_reclaim_data['can_reclaim']:
        print(f"❌ Kiki cannot reclaim her slot: {can_reclaim_data['reason']}")
        return
    
    # Step 7: Kiki reclaims her slot
    print("7. Kiki reclaiming her slot...")
    response = requests.post(
        f"{API_BASE}/api/games/{game_id}/reclaim-slot",
        json={"original_player_id": kiki_player_id, "player_name": "Kiki"}
    )
    if response.status_code != 200:
        print(f"❌ Failed to reclaim slot: {response.status_code}")
        return
    
    reclaim_data = json.loads(response.body)
    print(f"✅ Slot reclaimed: {reclaim_data}")
    
    # Step 8: Verify game state - should not have duplicate players
    print("8. Verifying game state...")
    response = requests.get(f"{API_BASE}/api/games/{game_id}")
    if response.status_code != 200:
        print(f"❌ Failed to get game state: {response.status_code}")
        return
    
    game_state = json.loads(response.body)
    players = game_state['players']
    
    print(f"✅ Game has {len(players)} players:")
    for i, player in enumerate(players):
        print(f"   Player {i}: {player['name']} (ID: {player['id']})")
    
    # Check for duplicate names
    player_names = [player['name'] for player in players]
    if len(player_names) != len(set(player_names)):
        print("❌ DUPLICATE PLAYER NAMES DETECTED!")
        print(f"   Player names: {player_names}")
        return
    
    # Check for duplicate IDs
    player_ids = [player['id'] for player in players]
    if len(player_ids) != len(set(player_ids)):
        print("❌ DUPLICATE PLAYER IDs DETECTED!")
        print(f"   Player IDs: {player_ids}")
        return
    
    print("✅ No duplicate players detected!")
    
    # Step 9: Verify turn logic is correct
    print("9. Verifying turn logic...")
    current_player_index = game_state['current_player_index']
    current_player = players[current_player_index]
    
    print(f"✅ Current player: {current_player['name']} (index: {current_player_index})")
    
    # The game should still be valid
    if game_state['game_started'] and len(players) == 2:
        print("✅ Game is still valid and playable")
    else:
        print("❌ Game state is invalid")
        return
    
    print("\n🎉 DUPLICATE PLAYER BUG FIX VERIFIED!")
    print("✅ Kiki can disconnect and reconnect without creating duplicates")
    print("✅ Game maintains proper player state and turn logic")
    print("✅ No more 'Kiki vs Kiki' issues!")

if __name__ == "__main__":
    asyncio.run(test_duplicate_player_fix())
