# Chess Analysis Tool

A local chess analysis application centered on engine-assisted game review, PGN analysis, and an embedded searchable chess database. It also includes normal chess-playing functionality, including playing against configured UCI engines, but its primary purpose is analysis rather than serving as a conventional chess game.

## Highlights

- Interactive board with legal move handling and game clocks.
- Live engine evaluation with principal variations.
- Deeper replay analysis of complete games.
- Experimental DeepAnalysis move annotations (`!`, `!!`, `?`, `??`) with documented human-oriented heuristics.
- Configurable UCI engines and reusable engine profiles.
- Human-vs-engine and engine-assisted play.
- Import and export of individual games in PGN format.
- Embedded SQLite chess database with PGN library import, search, stored-game loading, and position statistics.
- Browser UI with English, German, and French localization.

## Project structure

The project is composed of several Git submodules:

- `chess` — chess rules, notation, game loading/saving, and UCI engine integration.
- `chess-database` — embedded SQLite chess database and PGN library importer.
- `chess-api` — Spring Boot REST backend and application services.
- `chess-frontend` — React/Vite browser frontend.
- `spring-annotation-context-initializer-template` — reusable Spring annotation-context initializer dependency.

Clone the repository including its submodules:

```bash
git clone --recurse-submodules <repository-url>
```

For an existing clone:

```bash
git submodule update --init --recursive
```

## UCI engines

The application works with UCI-compatible chess engines such as Stockfish and Leela Chess Zero (Lc0).

### Recommended locations

The conventional engine directory for this project is:

- Windows: `C:\usr\games`
- Unix/Linux: `/usr/games`

On Unix-like systems, `/usr/games` is also the application's default automatic discovery directory. The directory can be overridden with the Java system property:

```text
-Dchess.engine.discovery.directory=/path/to/engines
```

Automatic discovery is deliberately conservative. Only executable files whose names contain `stockfish` or `lc0`, case-insensitively, are considered. A matching file is not accepted merely by name: it must also start successfully and complete a UCI handshake. This prevents unrelated executables in the discovery directory from being launched as chess engines.

Other UCI engines, and engines stored outside the discovery directory, can be added explicitly through the engine settings. On a graphical local installation the backend can open the operating system's file chooser and inspect the selected executable. WSL installations can use the Windows file chooser while the backend converts the selected path to its corresponding Linux path.

### Engine companion files

Some engines are not self-contained executables. Keep all runtime files required by an engine together with its executable unless the engine documentation explicitly says otherwise.

Lc0, for example, normally requires a neural-network weights file. Depending on the distributed build and operating system, it may also depend on DLLs or other runtime libraries. If these files are missing, the executable may exist and still fail to start or fail its UCI inspection. A practical installation layout is therefore to keep the executable, weights, and any required shared libraries in the same engine directory.

Engine configuration is persisted by default in:

```text
~/.chess/engine-configs.json
```

A different file can be selected with:

```text
-Dchess.engine.config.file=/path/to/engine-configs.json
```

The application supports reusable engine profiles. A profile combines one registered engine with concrete UCI option values and can be assigned independently to White CPU, Black CPU, live evaluation, and deep analysis.

## PGN and the chess database

PGN is the interchange format used for importing chess games.

There are two different import workflows:

- **Import New Game** accepts exactly one PGN game and opens it as the current game for analysis. The game is also stored in the local database.
- **Chess Database → Import PGN** is intended for database libraries containing one or many games.

Database source files therefore need to be in PGN format. Proprietary database formats must first be exported or converted to PGN with suitable external software.

The embedded SQLite database is created by default at:

```text
~/.chess/database/chess.db
```

The path can be overridden with:

```text
-Dchess.database.path=/path/to/chess.db
```

The database stores games and derived position information so that games can be searched and positions can be examined statistically. Search criteria currently include player names, year range, result, and minimum Elo.

### Large PGN libraries

Database imports run asynchronously and expose progress information, including bytes read and numbers of processed, imported, and skipped games. A running import can be cancelled.

Importing a large historical PGN collection is computationally and I/O intensive: games are parsed, legal moves are replayed, duplicate checks are performed, and position statistics are generated and written to SQLite. Depending on library size, storage performance, CPU speed, and the complexity of the games, an import may take **several hours**. This is expected for very large collections and should not be interpreted as a stalled application solely because the operation takes a long time.

The backend currently permits multipart uploads up to 20 GB. This is an upload limit, not a recommendation or a guarantee that a library of that size can be imported quickly or with modest disk usage.

## Building

The backend uses Java 21. The Maven reactor builds the Java modules and the `chess-api` build invokes the React/Vite frontend build before packaging the frontend into the Spring Boot application.

Typical full build:

```bash
mvn clean install
```

The frontend remains a normal npm/Vite project internally; Maven invokes `npm ci` and `npm run build` from `chess-frontend` during the backend resource-generation phase.

## Running

The packaged application is a Spring Boot application provided by `chess-api`. When running the backend directly during frontend development, the Vite development server proxies `/api` requests to:

```text
http://127.0.0.1:8080
```

Engine executables run as local child processes of the application. Consequently, the machine running the backend must have permission to execute the configured engines and access their companion files.

## Local application data

Unless overridden through system properties, persistent application data is stored below the current user's home directory:

```text
~/.chess/
├── engine-configs.json
└── database/
    └── chess.db
```

Backing up this directory preserves the local engine registry/profiles and chess database. Engine binaries themselves are not copied into this directory and need to be backed up separately if desired.

## Analysis design notes

The DeepAnalysis move-quality annotation concept, thresholds, architecture, and
known limitations are documented in
[`docs/deep-analysis-move-annotations.md`](docs/deep-analysis-move-annotations.md).

## Development status

This project is under active development. Analysis workflows, engine management, database features, localization, and frontend structure are evolving. Database schema and configuration formats may therefore change between development revisions.
