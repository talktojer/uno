import random
import string
import secrets
from typing import List, Optional, Dict
from models import Card, Player, GameState, CardColor, CardType


class UNOGame:
    def __init__(self, game_id: str):
        self.game_id = game_id
        self.game_code = self._generate_game_code()
        self.players: List[Player] = []
        self.deck: List[Card] = []
        self.discard_pile: List[Card] = []
        self.current_player_index = 0
        self.current_color: CardColor = CardColor.RED
        self.current_direction = 1
        self.game_started = False
        self.game_ended = False
        self.winner: Optional[str] = None
        self._initialize_deck()
    
    def _generate_game_code(self) -> str:
        """Generate a random 5-character game code"""
        # Use alphanumeric characters (0-9, A-Z)
        characters = string.ascii_uppercase + string.digits
        return ''.join(secrets.choice(characters) for _ in range(5))
    
    def _initialize_deck(self):
        """Initialize the UNO deck with all cards"""
        self.deck = []
        
        # Add number cards (0-9) for each color
        for color in [CardColor.RED, CardColor.BLUE, CardColor.GREEN, CardColor.YELLOW]:
            # One 0 card
            self.deck.append(Card(color=color, type=CardType.NUMBER, value=0))
            # Two of each 1-9
            for value in range(1, 10):
                self.deck.append(Card(color=color, type=CardType.NUMBER, value=value))
                self.deck.append(Card(color=color, type=CardType.NUMBER, value=value))
            
            # Add action cards (2 of each)
            for _ in range(2):
                self.deck.append(Card(color=color, type=CardType.SKIP))
                self.deck.append(Card(color=color, type=CardType.REVERSE))
                self.deck.append(Card(color=color, type=CardType.DRAW2))
        
        # Add wild cards (4 of each)
        for _ in range(4):
            self.deck.append(Card(color=CardColor.BLACK, type=CardType.WILD))
            self.deck.append(Card(color=CardColor.BLACK, type=CardType.WILD_DRAW4))
    
    def shuffle_deck(self):
        """Shuffle the deck"""
        random.shuffle(self.deck)
    
    def deal_cards(self):
        """Deal 7 cards to each player"""
        for player in self.players:
            player.cards = []
            for _ in range(7):
                if self.deck:
                    player.cards.append(self.deck.pop())
    
    def start_game(self):
        """Start the game"""
        if len(self.players) != 2:
            raise ValueError("Game requires exactly 2 players")
        
        self.shuffle_deck()
        self.deal_cards()
        
        # Place first card on discard pile
        while True:
            card = self.deck.pop()
            if card.type == CardType.NUMBER:
                self.discard_pile.append(card)
                self.current_color = card.color
                break
            else:
                self.deck.insert(0, card)
        
        # Clear all turn flags first
        for player in self.players:
            player.is_current_turn = False
        
        # Set first player's turn
        self.current_player_index = 0
        self.players[0].is_current_turn = True
        self.game_started = True
    
    def can_play_card(self, card: Card, player_index: int) -> bool:
        """Check if a card can be played"""
        if not self.game_started or self.winner:
            return False
        
        if player_index != self.current_player_index:
            return False
        
        # Wild cards can always be played
        if card.type in [CardType.WILD, CardType.WILD_DRAW4]:
            return True
        
        # Check color match
        if card.color == self.current_color:
            return True
        
        # Check value match for number cards
        if (card.type == CardType.NUMBER and 
            self.discard_pile and 
            self.discard_pile[-1].type == CardType.NUMBER and
            card.value == self.discard_pile[-1].value):
            return True
        
        # Check type match for action cards
        if (card.type != CardType.NUMBER and 
            self.discard_pile and 
            card.type == self.discard_pile[-1].type):
            return True
        
        return False
    
    def play_card(self, player_index: int, card_index: int, new_color: Optional[CardColor] = None) -> Dict:
        """Play a card and return the result"""
        if not self.can_play_card(self.players[player_index].cards[card_index], player_index):
            raise ValueError("Cannot play this card")
        
        player = self.players[player_index]
        card = player.cards.pop(card_index)
        
        # Add to discard pile
        self.discard_pile.append(card)
        
        # Handle card effects
        if card.type == CardType.NUMBER:
            self.current_color = card.color
        elif card.type == CardType.SKIP:
            self.current_color = card.color
            self._next_player()
        elif card.type == CardType.REVERSE:
            self.current_color = card.color
            self.current_direction *= -1
        elif card.type == CardType.DRAW2:
            self.current_color = card.color
            self._next_player()
            # Draw 2 cards for next player
            next_player = self.players[self.current_player_index]
            for _ in range(2):
                if self.deck:
                    next_player.cards.append(self.deck.pop())
        elif card.type == CardType.WILD:
            if new_color:
                self.current_color = new_color
        elif card.type == CardType.WILD_DRAW4:
            if new_color:
                self.current_color = new_color
            self._next_player()
            # Draw 4 cards for next player
            next_player = self.players[self.current_player_index]
            for _ in range(4):
                if self.deck:
                    next_player.cards.append(self.deck.pop())
        
        # Check for winner
        if len(player.cards) == 0:
            self.winner = player.id
            self.game_ended = True
            return {"game_over": True, "winner": player.id}
        
        # Move to next player if not skipped
        if card.type not in [CardType.SKIP, CardType.DRAW2, CardType.WILD_DRAW4]:
            self._next_player()
        
        return {"success": True, "next_player": self.current_player_index}
    
    def _next_player(self):
        """Move to the next player"""
        # Clear current turn flag from all players
        for player in self.players:
            player.is_current_turn = False
        
        # Move to next player
        self.current_player_index = (self.current_player_index + self.current_direction) % len(self.players)
        
        # Set turn flag for new current player
        self.players[self.current_player_index].is_current_turn = True
    
    def draw_card(self, player_index: int) -> Optional[Card]:
        """Draw a card for a player"""
        if player_index != self.current_player_index or not self.game_started:
            return None
        
        if not self.deck:
            # Reshuffle discard pile (except top card)
            if len(self.discard_pile) > 1:
                top_card = self.discard_pile.pop()
                self.deck = self.discard_pile.copy()
                self.discard_pile = [top_card]
                self.shuffle_deck()
            else:
                # If only one card in discard pile, can't reshuffle
                return None
        
        if self.deck:
            card = self.deck.pop()
            self.players[player_index].cards.append(card)
            # Don't advance turn here - let the WebSocket handler do it
            return card
        return None
    
    def get_game_state(self) -> GameState:
        """Get current game state"""
        return GameState(
            game_id=self.game_id,
            game_code=self.game_code,
            players=self.players,
            current_player_index=self.current_player_index,
            deck=self.deck,
            discard_pile=self.discard_pile,
            current_color=self.current_color,
            current_direction=self.current_direction,
            game_started=self.game_started,
            game_ended=self.game_ended,
            winner=self.winner
        )
    
    def get_draw_pile_count(self) -> int:
        """Get the number of cards in the draw pile"""
        return len(self.deck)
