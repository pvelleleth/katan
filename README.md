# Settler

Settler is a modern, browser-based strategy board game inspired by the mechanics of the classic board game Catan. Built with a high-performance Crystal backend and a reactive SvelteKit frontend, it provides a fast and polished multiplayer experience.

## 🚀 Features

- **Real-Time Multiplayer**: Built on top of WebSockets for instant state updates.
- **Classic Gameplay**: Hex-based map generation, resource production, trading, and building.
- **Instant Play**: Join games via lobby codes with minimal friction.
- **Server Authoritative**: Game rules, move validation, and match lifecycle managed by a secure backend engine.

## 🏗️ Project Structure

The repository is organized into two main sub-projects:

- **[settler/](./settler)**: The frontend application and API layer.
- **[settler-engine/](./settler-engine)**: The game engine and WebSocket server.

### Technology Stack

| Layer | Technologies |
| :--- | :--- |
| **Frontend** | [SvelteKit](https://kit.svelte.dev/), [TypeScript](https://www.typescriptlang.org/), [Tailwind CSS](https://tailwindcss.com/) |
| **Backend** | [Crystal](https://crystal-lang.org/) |
| **Database** | [PostgreSQL](https://www.postgresql.org/) (Supabase) |
| **ORM** | [Drizzle ORM](https://orm.drizzle.team/) |
| **Auth** | [Better Auth](https://better-auth.com/) |

## 🛠️ Getting Started

### Prerequisites

You'll need the following installed:
- [Bun](https://bun.sh/)
- [Crystal](https://crystal-lang.org/)
- [PostgreSQL](https://www.postgresql.org/)

### Local Development

To run the full stack, you need to start both the frontend and the engine.

#### 1. Frontend Setup (`settler/`)

```bash
cd settler
bun install
bun run dev
```

The app will be available at `http://localhost:5173`. Make sure to set up your environment variables in `.env` (see `.env.example`).

#### 2. Engine Setup (`settler-engine/`)

```bash
cd settler-engine
shards install
crystal run src/settler-engine.cr
```

The WebSocket server will typically run on port `8080`.

## 📜 Key Commands

### Frontend

- `bun run dev`: Start development server.
- `bun run build`: Create a production build.
- `bun run db:push`: Push database schema changes.
- `bun run db:studio`: Open Drizzle Studio.
- `bun run format`: Format code with Prettier.

### Backend Engine

- `crystal run src/settler-engine.cr`: Run the engine.
- `crystal spec`: Run test specifications.

## 👨‍💻 Contributing

For detailed guidelines on how to contribute to this project, please refer to [AGENTS.md](./AGENTS.md).
