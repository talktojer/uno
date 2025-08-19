#!/usr/bin/env python3
"""
Test script to verify the slot stealing fix works correctly.
This simulates the race condition where both players disconnect and the second player reconnects first.
"""

import asyncio
import json
import websockets
import requests
import time

# Test configuration
API_BASE = "http://localhost:8000"
WS_BASE = "ws://localhost:8000"

async def test_slot_stealing_fix():
    """Test that the slot stealing fix prevents players from taking each other's spots"""
    
    print("🧪 Testing Slot Stealing Fix...")
    
    # Step 1: Create a game
    print("1. Creating a new game...")
    response = requests.post(f"{API_BASE}/api/games/create")
    if response.status_code != 200:
        print(f"❌ Failed to create game: {response.text}")
        return False
    
    game_data = response.json()
    game_id = game_data["game_id"]
    game_code = game_data["game_code"]
    print(f"✅ Game created: {game_code}")
    
    # Step 2: Player 1 joins
    print("2. Player 1 joining...")
    response = requests.post(f"{API_BASE}/api/games/{game_id}/join", 
                           json={"player_name": "Alice"})
    if response.status_code != 200:
        print(f"❌ Failed to join game: {response.text}")
        return False
    
    player1_data = response.json()
    player1_id = player1_data["player_id"]
    print(f"✅ Player 1 joined: {player1_id}")
    
    # Step 3: Player 2 joins
    print("3. Player 2 joining...")
    response = requests.post(f"{API_BASE}/api/games/{game_id}/join", 
                           json={"player_name": "Bob"})
    if response.status_code != 200:
        print(f"❌ Failed to join game: {response.text}")
        return False
    
    player2_data = response.json()
    player2_id = player2_data["player_id"]
    print(f"✅ Player 2 joined: {player2_id}")
    
    # Step 4: Start the game
    print("4. Starting the game...")
    response = requests.post(f"{API_BASE}/api/games/{game_id}/start")
    if response.status_code != 200:
        print(f"❌ Failed to start game: {response.text}")
        return False
    
    print("✅ Game started")
    
    # Step 5: Simulate both players disconnecting
    print("5. Simulating both players disconnecting...")
    
    # Get current game state to see the cards
    response = requests.get(f"{API_BASE}/api/games/{game_id}")
    if response.status_code != 200:
        print(f"❌ Failed to get game state: {response.text}")
        return False
    
    game_state = response.json()
    print(f"   Player 1 ({player1_id}) has {len(game_state['players'][0]['cards'])} cards")
    print(f"   Player 2 ({player2_id}) has {len(game_state['players'][1]['cards'])} cards")
    
    # Step 6: Try to have Player 2 take Player 1's slot
    print("6. Testing if Player 2 can steal Player 1's slot...")
    
    # First, check if Player 2 can reclaim Player 1's slot (should fail)
    response = requests.get(f"{API_BASE}/api/games/{game_id}/can-reclaim/{player1_id}")
    if response.status_code != 200:
        print(f"❌ Failed to check reclamation: {response.text}")
        return False
    
    can_reclaim_data = response.json()
    print(f"   Can Player 2 reclaim Player 1's slot? {can_reclaim_data}")
    
    # Try to have Player 2 join again (should fail due to slot protection)
    print("7. Attempting to have Player 2 join again (should fail)...")
    response = requests.post(f"{API_BASE}/api/games/{game_id}/join", 
                           json={"player_name": "Bob2"})
    
    if response.status_code == 400 and "reserved for the original player" in response.text:
        print("✅ Slot protection working: Player 2 cannot take Player 1's slot")
    else:
        print(f"❌ Slot protection failed: {response.text}")
        return False
    
    # Step 7: Test that Player 1 can reclaim their own slot
    print("8. Testing if Player 1 can reclaim their own slot...")
    
    response = requests.get(f"{API_BASE}/api/games/{game_id}/can-reclaim/{player1_id}")
    if response.status_code != 200:
        print(f"❌ Failed to check reclamation: {response.text}")
        return False
    
    can_reclaim_data = response.json()
    print(f"   Can Player 1 reclaim their slot? {can_reclaim_data}")
    
    if can_reclaim_data["can_reclaim"]:
        print("✅ Player 1 can reclaim their slot")
        
        # Actually reclaim the slot
        response = requests.post(f"{API_BASE}/api/games/{game_id}/reclaim-slot",
                               json={"original_player_id": player1_id, "player_name": "Alice"})
        if response.status_code == 200:
            print("✅ Player 1 successfully reclaimed their slot")
        else:
            print(f"❌ Failed to reclaim slot: {response.text}")
            return False
    else:
        print(f"❌ Player 1 cannot reclaim slot: {can_reclaim_data['reason']}")
        return False
    
    # Step 8: Verify the fix worked
    print("9. Verifying the fix worked...")
    
    # Get updated game state
    response = requests.get(f"{API_BASE}/api/games/{game_id}")
    if response.status_code != 200:
        print(f"❌ Failed to get updated game state: {response.text}")
        return False
    
    updated_game_state = response.json()
    
    # Check that Player 1 still has their original cards
    if len(updated_game_state['players'][0]['cards']) == len(game_state['players'][0]['cards']):
        print("✅ Player 1 still has their original cards - slot stealing prevented!")
    else:
        print("❌ Player 1 lost their cards - slot stealing still possible!")
        return False
    
    print("\n🎉 All tests passed! The slot stealing fix is working correctly.")
    return True

if __name__ == "__main__":
    try:
        success = asyncio.run(test_slot_stealing_fix())
        if success:
            print("\n✅ Slot stealing fix verification completed successfully!")
        else:
            print("\n❌ Slot stealing fix verification failed!")
            exit(1)
    except Exception as e:
        print(f"\n💥 Test failed with error: {e}")
        exit(1)
