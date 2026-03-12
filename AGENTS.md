# Repository Guidelines

## Project Structure & Module Organization
This repository contains two apps:

- `katan-engine/`: Crystal websocket game engine. Main entrypoint is `src/katan-engine.cr`; domain logic lives under `src/domain`, application services under `src/application`, and websocket transport code under `src/transport`. Tests live in `katan-engine/spec`.
- `tradeisles/`: SvelteKit frontend and API layer. Routes live in `src/routes`, shared browser/server code in `src/lib`, database schema and client code in `src/lib/server/db`, static assets in `static`, and generated Drizzle migrations in `drizzle/`.

## Build, Test, and Development Commands
Run commands from the relevant subproject directory.

- `cd tradeisles && bun run dev`: start the SvelteKit app locally.
- `cd tradeisles && bun run build`: create a production build.
- `cd tradeisles && bun run preview`: serve the production build locally.
- `cd tradeisles && bun run check`: run SvelteKit sync plus TypeScript and Svelte checks.
- `cd tradeisles && bun run lint`: check formatting with Prettier.
- `cd tradeisles && bun run format`: apply Prettier formatting.
- `cd tradeisles && bun run db:generate|db:push|db:migrate|db:studio`: manage Drizzle schema changes.
- `cd katan-engine && crystal run src/katan-engine.cr`: run the websocket server.
- `cd katan-engine && crystal spec`: run Crystal specs.

## Coding Style & Naming Conventions
Follow the formatter and language defaults already in use.

- Svelte/TypeScript uses tabs, single quotes, and no trailing commas via `tradeisles/.prettierrc`.
- Keep Svelte route files in Kit conventions such as `+page.svelte`, `+page.server.ts`, and `+server.ts`.
- Use `camelCase` for TS variables/functions, `PascalCase` for types/components, and `snake_case.cr` for Crystal filenames.
- Keep Crystal namespaces aligned with folders, for example `Katan::Engine::Transport::WebSocket`.

## Testing Guidelines
Frontend quality checks currently rely on `bun run check` and `bun run lint`. Add automated tests alongside new UI or API behavior when introducing a test runner.

Crystal tests belong in `katan-engine/spec/*_spec.cr`. Name examples around observable behavior and keep them focused on domain or service outcomes.

## Commit & Pull Request Guidelines
Recent commits use short, imperative summaries such as `built out real time lobby building`. Keep commit subjects brief, present tense, and scoped to one change.

Pull requests should include:

- a clear summary of behavior changes
- linked issues or follow-up tasks when relevant
- screenshots or short recordings for `tradeisles` UI work
- notes about schema, migration, or websocket protocol changes
