# UNO Game - Two Player Clone

A complete two-player UNO card game implementation built with FastAPI backend and Flutter frontend, featuring an **intuitive and streamlined game joining process**.

## ✨ New Features & Improvements

### 🎯 **Revamped Game Joining Experience**
- **Progressive disclosure** interface that guides users step-by-step
- **Mobile-first design** with touch-friendly interactions
- **Simplified workflow** - no more confusing multiple input fields
- **Clear visual hierarchy** with logical action grouping
- **Streamlined rejoin process** for disconnected players

> 📖 **See [Game Joining UX Improvements](GAME_JOINING_UX_IMPROVEMENTS.md) for detailed documentation**

## Features

- **Complete UNO Game Logic**: All standard UNO rules implemented
- **Real-time Gameplay**: WebSocket support for live updates
- **Beautiful UI**: Modern Flutter interface with card animations
- **Two Player Support**: Perfect for head-to-head matches
- **All Card Types**: Numbers, Skip, Reverse, Draw2, Wild, and Wild Draw4
- **Responsive Design**: Works on desktop and mobile
- **Intuitive UX**: Streamlined game joining and management

## Game Rules

The game follows standard UNO rules:
- Each player starts with 7 cards
- Match cards by color, number, or action type
- Special action cards have unique effects:
  - **Skip**: Next player loses their turn
  - **Reverse**: Changes play direction
  - **Draw2**: Next player draws 2 cards and loses turn
  - **Wild**: Change the current color
  - **Wild Draw4**: Change color and next player draws 4 cards
- First player to play all their cards wins!

## Architecture

- **Backend**: FastAPI with WebSocket support
- **Frontend**: Flutter web application with mobile-first design
- **Real-time Updates**: WebSocket-based game state synchronization
- **Docker**: Containerized deployment

## Prerequisites

- Docker and Docker Compose
- Flutter SDK (for development)
- Python 3.8+ (for development)

## Quick Start

### Using Docker (Recommended)

1. **Clone and navigate to the project:**
   ```bash
   cd /home/jer/game
   ```

2. **Start the services:**
   ```bash
   docker-compose up --build
   ```

3. **Access the game:**
   - Frontend: http://localhost:3000
   - Backend API: http://localhost:8000

### Manual Setup

1. **Backend Setup:**
   ```bash
   cd backend
   pip install -r requirements.txt
   python main.py
   ```

2. **Frontend Setup:**
   ```bash
   cd frontend
   flutter pub get
   flutter run -d web-server --web-port 3000
   ```

## How to Play

### 🆕 **New Improved Flow**

1. **Enter Your Name**: Start by entering your player name
2. **Choose Action**: Select what you want to do:
   - **Create New Game**: Start a new UNO game
   - **Join Existing Game**: Enter a game code to join
   - **Rejoin Game**: Reconnect to a game you were playing
3. **Follow the Prompts**: Each action has clear, step-by-step guidance
4. **Start Playing**: Once both players join, click "Start Game"

### Traditional Flow (Still Supported)
- **Create a Game**: Click "Create Game" to start a new UNO game
- **Join the Game**: Enter your name and click "Join Game"
- **Start Playing**: Once both players join, click "Start Game"
- **Gameplay**: 
  - Click on playable cards to play them
  - Use "Draw Card" button when you can't play
  - Match colors, numbers, or action types
  - First to play all cards wins!

## API Endpoints

### Game Management
- `POST /api/games` - Create a new game
- `GET /api/games/{game_id}` - Get game state
- `POST /api/games/{game_id}/join` - Join a game
- `POST /api/games/{game_id}/start` - Start the game

### Game Actions
- `POST /api/games/{game_id}/play` - Play a card
- `POST /api/games/{game_id}/draw` - Draw a card

### WebSocket
- `WS /ws/{game_id}/{player_id}` - Real-time game updates

## Development

### Backend Structure
```
backend/
├── main.py              # FastAPI application with game logic
├── requirements.txt     # Python dependencies
└── Dockerfile          # Backend container configuration
```

### Frontend Structure
```
frontend/
├── lib/
│   ├── main.dart       # Main Flutter application
│   └── config/         # Mobile and responsive configuration
├── pubspec.yaml        # Flutter dependencies
└── Dockerfile          # Frontend container configuration
```

### Key Components

- **UNOGame Class**: Complete game logic implementation
- **Card System**: All UNO card types with proper rules
- **Player Management**: Turn-based gameplay with validation
- **Real-time Updates**: WebSocket-based state synchronization
- **Beautiful UI**: Card animations and modern design
- **Responsive Design**: Mobile-first approach with adaptive layouts

## Customization

### Adding New Card Types
1. Update `CardType` enum in `backend/main.py`
2. Add logic in `play_card` method
3. Update frontend card rendering

### Modifying Game Rules
1. Edit validation logic in `can_play_card`
2. Update card effects in `play_card`
3. Modify frontend UI accordingly

## Troubleshooting

### Common Issues

1. **Port Already in Use**
   - Change ports in `docker-compose.yml`
   - Kill existing processes using those ports

2. **CORS Errors**
   - Ensure backend is running on port 8000
   - Check CORS configuration in backend

3. **Game Not Starting**
   - Verify both players have joined
   - Check backend logs for errors

4. **Cards Not Playing**
   - Ensure it's your turn
   - Check if card matches current color/number

### Debug Mode

Enable debug logging by setting environment variables:
```bash
export PYTHONUNBUFFERED=1
export FLUTTER_DEBUG=1
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is open source and available under the MIT License.

## Acknowledgments

- UNO is a trademark of Mattel
- Built with FastAPI and Flutter
- Inspired by classic card game mechanics
- UX improvements based on modern design principles

---

**Enjoy playing UNO with the new improved experience!** 🃏🎨✨
