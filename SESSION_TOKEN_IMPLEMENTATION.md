# Session Token Implementation for UNO Game Rejoining

## Overview
This document describes the implementation of session tokens to fix the broken rejoining functionality in the UNO game. The solution provides persistent session tracking and makes both link-based rejoining and manual rejoin work reliably.

## Problem Statement
The original rejoining functionality was broken because:
1. **Link-based rejoining**: When users clicked game links, they were always shown a "join" dialog instead of checking if they could rejoin
2. **Manual rejoin button**: The "Rejoin Game" button relied on WebSocket disconnection tracking, which was unreliable
3. **No persistent tracking**: There was no way to identify returning players from links or browser sessions

## Solution: Session Tokens
We implemented a session token system that:
- Generates unique tokens when players join games
- Stores tokens in browser local storage
- Provides endpoints to check session validity
- Enables intelligent rejoin suggestions

## Backend Changes

### 1. Global State Addition
```python
# Track player sessions for rejoining
player_sessions: Dict[str, Dict[str, str]] = {}  # game_id -> {player_name -> session_token}
```

### 2. Modified Join Endpoints
Both `/api/games/{game_id}/join` and `/api/games/join-by-code` now:
- Generate a unique session token using `secrets.token_urlsafe(32)`
- Store the token in `player_sessions[game_id][player_name]`
- Return the token in the response

**Example Response:**
```json
{
  "player_id": "player_1",
  "game_id": "game_123",
  "session_token": "abc123def456...",
  "message": "Player joined successfully"
}
```

### 3. New Session Check Endpoint
```python
@app.get("/api/games/{game_id}/session/{player_name}")
async def check_player_session(game_id: str, player_name: str):
    """Check if a player has an active session in this game"""
```

**Response:**
```json
{
  "has_session": true,
  "can_rejoin": true,
  "message": "Found active session for 'Alice' - can rejoin"
}
```

### 4. Enhanced Game Code Endpoint
```python
@app.get("/api/games/code/{game_code}")
```
Now includes `disconnected_players` count to help frontend make intelligent decisions.

## Frontend Changes

### 1. Session Token Storage
When joining games, session tokens are automatically stored in browser local storage:
```dart
// Store session token for potential rejoin
if (data['session_token'] != null) {
  final storageKey = 'uno_session_${data['game_id']}_$playerName';
  html.window.localStorage[storageKey] = data['session_token'];
}
```

### 2. Enhanced Link Processing
`_checkUrlForGameCode()` now calls `_checkGameCodeAndSuggestAction()` which:
- Checks for disconnected players in the game
- Scans local storage for existing session tokens
- Suggests appropriate action (rejoin vs. join)

### 3. Smart Rejoin Dialog
`_showRejoinOrJoinDialog()` provides users with clear choices:
- **Rejoin Game**: For returning players
- **Join as New Player**: For new players
- **Cancel**: To go back to home

### 4. Enhanced Rejoin Logic
`_rejoinGame()` now:
1. Checks if player has an active session
2. Verifies rejoin eligibility
3. Provides clear feedback for different scenarios

## How It Works

### Scenario 1: New Player with Link
1. User clicks `/ABC12` link
2. System checks game status (no disconnected players)
3. Shows "Join as New Player" dialog
4. Player joins normally with session token generated

### Scenario 2: Returning Player with Link
1. User clicks `/ABC12` link (same game they played before)
2. System detects existing session token in local storage
3. Shows "Rejoin or Join" dialog
4. User chooses rejoin and enters same name
5. System validates session and restores player state

### Scenario 3: Manual Rejoin Button
1. User clicks "Rejoin Game" button
2. System checks for active sessions
3. If session exists, proceeds with rejoin
4. If no session, shows helpful error message

## Benefits

1. **Fixes Link-based Rejoining**: Users can now rejoin games directly from links
2. **Reliable Manual Rejoin**: Session tokens provide persistent tracking
3. **Better UX**: Clear guidance on when to rejoin vs. join
4. **Scalable**: Foundation for future features like game history
5. **Secure**: Uses cryptographically secure random tokens

## Testing

### Backend Testing
```bash
cd backend
python test_rejoin_endpoints.py
```

### Frontend Testing
1. Create a game and note the game code
2. Join the game as a player
3. Close the browser tab
4. Click the game link again
5. Verify the rejoin dialog appears
6. Enter the same player name and verify rejoin works

## Future Enhancements

1. **Session Expiration**: Add TTL to session tokens
2. **Game History**: Track completed games per session
3. **Player Statistics**: Store player performance data
4. **Multi-device Support**: Sync sessions across devices
5. **Admin Panel**: View and manage active sessions

## Security Considerations

- Session tokens are cryptographically secure (32 bytes random)
- Tokens are stored locally (not transmitted unnecessarily)
- No sensitive game data in tokens
- Tokens can be easily invalidated by clearing local storage

## Conclusion

The session token implementation provides a robust, user-friendly solution to the rejoining problem. It maintains backward compatibility while adding powerful new capabilities for tracking player participation and enabling seamless game restoration.
