# Chess Analysis Tool

Chess Analysis Tool is a local, analysis-oriented chess application built around UCI engines and an embedded game database. Its primary purpose is to **study games and positions**, compare engine evaluations, replay games under deeper analysis, and work with personal or public PGN libraries.

It is not intended primarily as a conventional chess game. Nevertheless, it includes the game functionality needed for a complete analysis workflow: you can start and play games, play against configured engines, import a single game, export the current game, and then analyse the resulting positions or game history.

## Highlights

- Interactive chessboard, move history, clocks, and normal game lifecycle.
- Live UCI engine evaluation and multi-line analysis.
- Deep analysis/replay of complete games.
- Multiple UCI engines, reusable engine profiles, and separate profile assignments for White, Black, live evaluation, and deep analysis.
- Play against a configured engine when desired.
- Import/export of the current game in PGN.
- Embedded SQLite chess database for large PGN libraries.
- Search stored games by players, years, result, and Elo criteria.
- Position and move statistics derived from the local game database.
- English, German, and French browser-side UI localization.

## Project structure

The repository is a parent project with Git submodules:

- `chess` — chess rules, game model, notation/PGN handling, simulations, and UCI engine integration.
- `chess-database` — embedded SQLite game library, PGN bulk import, search, and position statistics.
- `chess-api` — Spring Boot application layer connecting the frontend, chess core, engines, analysis, and database.
- `chess-frontend` — React/TypeScript/Vite user interface.
- `spring-annotation-context-initializer-template` — supporting Spring initialization template used by the chess core.

Clone the project with its submodules initialized, for example with `git clone --recurse-submodules ...`. If the repository has already been cloned without submodules, initialize them before building.

## UCI engines

Engines are external programs and are not bundled with this repository. The application can work with UCI-compatible engines such as Stockfish and Leela Chess Zero (Lc0).

### Recommended engine locations

For the standard project layout, place engine distributions in:

- **Windows:** `C:\usr\games`
- **Unix/Linux:** `/usr/games`

The automatic discovery service uses `/usr/games` as its default discovery path; with the project's normal Windows layout this corresponds to `C:\usr\games`. A different directory can be configured with the Java system property `chess.engine.discovery.directory`.

Automatic discovery is deliberately conservative. It scans only regular executable files whose **filename contains `stockfish` or `lc0`**, case-insensitively, and then verifies each candidate with an actual UCI handshake. It does not blindly execute every file found in the directory. Paths resolving to the same executable are de-duplicated.

This filename restriction applies to **automatic discovery only**. Other UCI engines, and engines stored in other directories, can be added explicitly through the engine configuration workflow. In a local graphical session the backend can open the operating system's native file chooser; Windows/WSL path selection is supported as well. The selected file still has to be an executable that responds correctly to UCI inspection.

### Engine companion files

Do not assume that an engine consists of a single executable. Keep the complete engine distribution together unless its own documentation says otherwise.

This is particularly important for **Lc0/Leela Chess Zero**. Lc0 requires a compatible neural-network weights file to perform useful chess evaluation, and some Windows distributions also depend on DLLs or other runtime libraries. The executable, weights, and required runtime files should therefore remain in the same engine directory when that is how the distribution is packaged. The Chess Analysis Tool registers the executable; it does not install or reconstruct missing third-party engine dependencies.

Engine definitions and profiles are persisted by default in `~/.chess/engine-configs.json`. This can be changed with `chess.engine.config.file`.

## PGN and the chess database

There are two intentionally different PGN workflows:

1. **Import New Game** loads exactly one PGN game into the current-game/analysis workflow.
2. **Chess Database → Import PGN** is intended for PGN files containing complete libraries or many games.

Files imported as chess databases must be in **PGN (Portable Game Notation)** format. The database importer streams the source, tracks import progress, and builds both game records and position/move statistics in the embedded SQLite database.

The database is stored by default at `~/.chess/database/chess.db`; use the `chess.database.path` Java system property to choose another location.

### Large libraries

A large PGN file is not merely copied into SQLite. Games have to be parsed and replayed, metadata stored, duplicates handled, and position/move statistics aggregated. Consequently, importing a large collection may take **many minutes or several hours**, depending on the number of games, the number of positions, CPU performance, and storage speed.

Bulk import runs as a background job with observable progress and controlled cancellation. Import data is staged so an incomplete, cancelled, or failed import is not exposed as a successfully imported library. The backend currently allows multipart PGN uploads up to 20 GB, but that limit should not be interpreted as a promise that files of that size will import quickly.

## Building the application

The backend application uses **Java 21**. The core and database modules currently target Java 17 bytecode and are consumed by the Java 21 Spring Boot application. Maven builds the Java modules through the parent reactor.

The frontend uses React, TypeScript, Vite, and npm. The `chess-api` Maven build invokes `npm ci` followed by `npm run build` in `chess-frontend`, then packages the generated frontend into the Spring Boot application. A working Node/npm installation is therefore required for a complete Maven package build.

From the project root, the intended complete build is:

```bash
mvn clean package
```

After a successful package build, the Spring Boot artifact is produced as `chess-api/target/chess-app.jar` and can be started with:

```bash
java -jar chess-api/target/chess-app.jar
```

Spring Boot uses port `8080` by default unless configured otherwise.

## Local-first design

The application is designed around local engine executables and a local SQLite database. Engine file selection therefore refers to files visible to the machine running the backend, not arbitrary executables uploaded through a browser. This also allows heavyweight analysis and large database imports to remain on the user's own machine.

## Development status

The project is under active development. In particular, the frontend and several larger backend classes are being refactored incrementally into smaller, responsibility-focused modules while preserving existing behavior and API contracts.
