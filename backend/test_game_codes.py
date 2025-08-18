#!/usr/bin/env python3
"""
Test script for the UNO game code functionality
"""

import requests
import json

# Test configuration
BASE_URL = "http://localhost:8000"

def test_game_creation():
    """Test creating a new game and getting a game code"""
    print("Testing game creation...")
    
    try:
        response = requests.post(f"{BASE_URL}/api/games/create")
        if response.status_code == 200:
            data = response.json()
            print(f"✅ Game created successfully!")
            print(f"   Game ID: {data['game_id']}")
            print(f"   Game Code: {data['game_code']}")
            print(f"   Message: {data['message']}")
            return data['game_code']
        else:
            print(f"❌ Failed to create game: {response.status_code}")
            return None
    except Exception as e:
        print(f"❌ Error creating game: {e}")
        return None

def test_get_game_by_code(game_code):
    """Test getting game information by game code"""
    print(f"\nTesting get game by code: {game_code}")
    
    try:
        response = requests.get(f"{BASE_URL}/api/games/code/{game_code}")
        if response.status_code == 200:
            data = response.json()
            print(f"✅ Game found by code!")
            print(f"   Game ID: {data['game_id']}")
            print(f"   Game Code: {data['game_code']}")
            print(f"   Player Count: {data['player_count']}")
            print(f"   Status: {data['status']}")
            return True
        else:
            print(f"❌ Failed to get game by code: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Error getting game by code: {e}")
        return False

def test_join_game_by_code(game_code, player_name):
    """Test joining a game by game code"""
    print(f"\nTesting join game by code: {game_code} with player: {player_name}")
    
    try:
        response = requests.post(
            f"{BASE_URL}/api/games/join-by-code",
            json={
                "game_code": game_code,
                "player_name": player_name
            }
        )
        if response.status_code == 200:
            data = response.json()
            print(f"✅ Joined game successfully!")
            print(f"   Player ID: {data['player_id']}")
            print(f"   Game ID: {data['game_id']}")
            print(f"   Message: {data['message']}")
            return True
        else:
            print(f"❌ Failed to join game: {response.status_code}")
            print(f"   Response: {response.text}")
            return False
    except Exception as e:
        print(f"❌ Error joining game: {e}")
        return False

def test_list_games():
    """Test listing all games to see game codes"""
    print(f"\nTesting list games...")
    
    try:
        response = requests.get(f"{BASE_URL}/api/games")
        if response.status_code == 200:
            data = response.json()
            print(f"✅ Games listed successfully!")
            print(f"   Total games: {len(data['games'])}")
            for game in data['games']:
                print(f"   - Game: {game['game_id']} | Code: {game['game_code']} | Status: {game['status']}")
            return True
        else:
            print(f"❌ Failed to list games: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Error listing games: {e}")
        return False

def main():
    """Run all tests"""
    print("🧪 Testing UNO Game Code Functionality")
    print("=" * 50)
    
    # Test 1: Create a game
    game_code = test_game_creation()
    if not game_code:
        print("❌ Cannot continue tests without a game code")
        return
    
    # Test 2: Get game by code
    if not test_get_game_by_code(game_code):
        print("❌ Get game by code test failed")
        return
    
    # Test 3: Join game by code
    if not test_join_game_by_code(game_code, "TestPlayer"):
        print("❌ Join game by code test failed")
        return
    
    # Test 4: List all games
    test_list_games()
    
    print("\n" + "=" * 50)
    print("🎉 All tests completed!")

if __name__ == "__main__":
    main()
