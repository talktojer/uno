# UNO Game Sharing System

This document describes the new game sharing system that allows players to join games using simple 5-character codes.

## Features

### Game Codes
- Each game is automatically assigned a unique 5-character code (e.g., "ABC12", "XY9Z3")
- Codes consist of uppercase letters (A-Z) and numbers (0-9)
- Codes are generated randomly and are guaranteed to be unique

### Sharing Games
- **From Game Menu**: After creating a game, the game code is displayed prominently
- **From Inside Game**: Use the share button (📤) in the game screen to get the game code
- **Direct URL**: Games can be accessed directly via `https://uno.jersweb.net/ABC12`

### Joining Games
- **By Code**: Enter the 5-character game code in the "Game Code" field
- **By Game ID**: Still supported for backward compatibility
- **Auto-detection**: URLs with game codes automatically populate the join form

## How It Works

### Backend Changes
1. **Game Creation**: Each new game gets a unique 5-character code
2. **Code Mapping**: Games are tracked by both ID and code for easy lookup
3. **New Endpoints**:
   - `POST /api/games/join-by-code` - Join a game using its code
   - `GET /api/games/code/{game_code}` - Get game info by code

### Frontend Changes
1. **URL Routing**: Handles game code URLs like `/ABC12`
2. **Game Code Input**: Dedicated field for entering game codes
3. **Share Functionality**: Copy game URLs to clipboard
4. **Auto-population**: Game codes from URLs automatically fill the join form

### Nginx Configuration
- Updated to handle Flutter web routing
- Game code routes (5-character patterns) properly route to the app

## User Experience

### Creating a Game
1. Enter your name
2. Click "Create Game"
3. Game code is displayed (e.g., "ABC12")
4. Share the code or full URL with others

### Joining a Game
1. **By Code**: Enter the 5-character code and your name, click "Join by Code"
2. **By URL**: Navigate directly to `https://uno.jersweb.net/ABC12`
3. **From List**: Click the copy button next to any available game

### Sharing While Playing
1. Click the share button (📤) in the game screen
2. Copy the game code or full URL
3. Share with others via text, email, social media, etc.

## Technical Details

### Code Generation
- Uses Python's `secrets` module for cryptographically secure random generation
- Checks for uniqueness before assigning codes
- Format: 5 characters from A-Z and 0-9

### URL Structure
- Base URL: `https://uno.jersweb.net`
- Game URLs: `https://uno.jersweb.net/ABC12`
- All routes fall back to the main app for proper Flutter routing

### Backward Compatibility
- Existing game IDs still work
- Old join methods remain functional
- Game codes are additional, not replacements

## Security Considerations

- Game codes are randomly generated and not predictable
- No sensitive information is exposed in the codes
- Codes only provide access to join games, not admin control

## Future Enhancements

- QR code generation for easy mobile sharing
- Social media integration
- Game code expiration for inactive games
- Private/public game options
