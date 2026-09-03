# Settler Engine

The high-performance game engine for [Settler](../README.md). Written in [Crystal](https://crystal-lang.org/) for speed and type safety, this server manages game sessions, validates moves, and provides real-time state updates via WebSockets.

## 🚀 Features

- **In-Memory State**: Fast game session management.
- **WebSocket Server**: Low-latency communication for multiplayer.
- **Server-Authoritative Logic**: Secure move validation and turn-based mechanics.
- **Persistence**: Integrates with PostgreSQL via `crystal-pg` for match history and events.

## 🛠️ Installation

1.  [Install Crystal](https://crystal-lang.org/install/).
2.  Install dependencies:
    ```bash
    shards install
    ```

## 🏗️ Development

To start the engine in development mode:
```bash
crystal run src/settler-engine.cr
```

The server listens on `0.0.0.0:8080` by default. Set `HOST` and `PORT` to
override the bind address, and set `WS_BOOTSTRAP_SECRET` (or
`BETTER_AUTH_SECRET`) to the same secret used by the frontend. Set
`DATABASE_URL` to enable game event persistence.

To run the specs (tests):
```bash
crystal spec
```

## 📁 Project Structure

- `src/domain/`: Core game logic and entities.
- `src/application/`: Application services and business logic.
- `src/transport/`: WebSocket server and protocol handling.
- `spec/`: Automated tests and specifications.

## 📄 License

This project is licensed under the MIT License. See [LICENSE](./LICENSE) for details.

## 👨‍💻 Contributing

Please see the root [README](../README.md) and [AGENTS.md](../AGENTS.md) for contribution guidelines.
