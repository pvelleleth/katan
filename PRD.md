# Product Requirements Document (PRD)

## Product Name
Settler

## Vision
Build the best browser-based strategy trading board game inspired by the mechanics of the classic board game Catan. The product, Settler, recreates the core gameplay loop of online settlement-style play—hex tile resource production, settlement and city building, trading between players, road expansion, and victory-point-based competition—while providing a modern multiplayer web experience. Players should be able to instantly join games in the browser with minimal friction while enjoying competitive ranked play, social features, and a polished modern UX.

## Design Inspiration
The gameplay model is based on the well-known mechanics popularized by the board game Catan: hex-based map generation, dice-driven resource production, player trading, road networks, settlement upgrades, and victory points. This project aims to build a modern online implementation of those mechanics with improved UX, multiplayer infrastructure, and competitive features.

## Problem
Existing browser implementations of settlement-style board games have several shortcomings:
- Slow or clunky UX
- Limited competitive play infrastructure
- Paywalls around core gameplay features
- Weak social systems

Players want a fast, accessible multiplayer strategy experience they can launch instantly in the browser.

## Goals
Primary goals:
- Allow players to start a game in under 10 seconds
- Provide smooth real-time multiplayer
- Enable competitive ranked ladder play

Secondary goals:
- Build a recognizable independent brand
- Create monetization via cosmetics and optional subscriptions

## Target Users
1. Casual players who want quick games with friends
2. Competitive players who want ranked play
3. Board game enthusiasts who enjoy trading and strategy

## Core Features (MVP)

### Instant Play
- Guest mode (no signup required)
- Create game lobby
- Join game via code

### Multiplayer Game Engine
- Turn-based gameplay
- Server-authoritative rules
- Dice rolling
- Resource allocation
- Trading system
- Building mechanics

### Real-Time Multiplayer
- WebSocket-based communication
- Live board updates
- Player reconnect support

### Lobby System
- Create lobby
- Join lobby
- Player ready state

### Accounts
- Optional login
- Upgrade guest account to registered account

### Match Results
- Store completed matches
- Basic player statistics

## Non-Goals (MVP)
- Mobile apps
- Complex tournament systems
- Advanced analytics

## Technical Architecture

### Frontend
Framework: SvelteKit

Responsibilities:
- UI rendering
- Game client
- Lobby interface

### Backend
Language: Crystal

Responsibilities:
- Game state engine
- WebSocket server
- Move validation
- Match lifecycle

### Database
Provider: Supabase Postgres

Stores:
- Users
- Players
- Match history
- Basic stats

### Realtime State
Active game sessions stored in memory on the game server.

## Data Model (Simplified)

Users
- id
- email
- created_at

Players
- id
- user_id
- rating
- games_played

Games
- id
- created_at
- status

GameParticipants
- game_id
- player_id

## Success Metrics
- Daily active users
- Average games per user
- Game completion rate

## Monetization
- Cosmetic upgrades
- Optional subscription
- Ads for free users

## Roadmap

Phase 1: Core Game
- Lobby
- Multiplayer gameplay
- Guest accounts

Phase 2: Competitive Play
- Ranking system
- Matchmaking

Phase 3: Social Layer
- Friends
- Chat
- Private tournaments

## Risks
- Multiplayer synchronization complexity
- Player cheating
- Trademark/IP concerns around game mechanics

## Future Opportunities
- Mobile support
- Additional board game modes
- Competitive leagues

