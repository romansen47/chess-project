# Chess Analysis Tool

Chess Analysis Tool (CAT) is a local chess application centered on engine-assisted game review, PGN analysis, understandable move-quality annotations, and an embedded searchable chess database. It also supports normal play, including human-vs-engine and engine-vs-engine games.

CAT is intended to sit between lightweight online analysis and large professional chess suites: **more depth and control than a typical web analysis, with substantially less overhead than a traditional all-in-one chess database environment.** Games, engine configuration, analysis data, and the local database remain on the user's machine.

## Who is CAT for?

CAT is primarily aimed at chess players who want to analyze seriously without turning their analysis workflow into a large software ecosystem.

It may be especially useful for:

- **Club players and ambitious hobby players** who want to review games with engine lines, deeper replay analysis, and compact move-quality annotations.
- **Players with their own PGN collections** who want a searchable local database and position statistics without depending on a cloud service.
- **Engine enthusiasts** who want to configure and compare UCI engines such as Stockfish and Lc0, maintain reusable engine profiles, and run engine-assisted or engine-vs-engine play.
- **Offline- and privacy-oriented users** who prefer their games, database, and analysis configuration to stay on their own machine.
- **Technically interested chess players** who want the reasoning behind move annotations to remain visible and testable.

CAT is not intended to replace every feature of mature professional suites. Its focus is a compact local workflow built around PGN, UCI engines, a searchable database, and explainable analysis.

## Highlights

- Interactive board with legal move handling and game clocks.
- Live engine evaluation with principal variations.
- Deeper replay analysis of complete games.
- Explainable move annotations: `!`, `!!`, `?`, and `??`.
- Configurable UCI engines and reusable engine profiles.
- Human-vs-engine and engine-vs-engine play.
- Import and export of individual games in PGN format.
- Embedded SQLite chess database with PGN library import, search, stored-game loading, and position statistics.
- Browser UI with English, German, French, Italian, and Spanish localization.
- Optional runtime debug mode with diagnostic analysis-PGN export.

## Quick start

### Requirements

For a released CAT JAR:

- Java 21;
- a modern web browser;
- at least one local UCI engine if engine analysis or computer play is required.

For building from source, additionally install:

- Maven;
- Node.js **20.19 or newer** and npm, because the Maven build invokes the frontend build. CI and release builds currently pin **Node.js 24.21.0 LTS / npm 11.19.0** for reproducibility.

### Clone

The project uses Git submodules:

```bash
git clone --recurse-submodules <repository-url>
cd chess-project
```

For an existing clone:

```bash
git submodule update --init --recursive
```

### Build

Build and test the complete project:

```bash
mvn clean install
```

The executable Spring Boot JAR is produced at:

```text
chess-api/target/chess-app.jar
```

The Maven reactor also runs `npm ci` and `npm run build` in `chess-frontend` and embeds the resulting frontend into the JAR.

### Run

Start a locally built application:

```bash
java -jar chess-api/target/chess-app.jar
```

Then open:

```text
http://127.0.0.1:8080
```

A released artifact can be started in the same way, for example:

```bash
java -jar cat-v0.1.0.jar
```

Engine executables run as child processes of CAT. The user running the Java process must therefore have permission to execute the configured engines and read their companion files.

### Debug mode

Debug-only functionality is disabled by default.

Enable it with the JVM system property:

```bash
java -DdebugMode -jar chess-api/target/chess-app.jar
```

or explicitly:

```bash
java -DdebugMode=true -jar chess-api/target/chess-app.jar
```

Disable it explicitly with:

```bash
java -DdebugMode=false -jar chess-api/target/chess-app.jar
```

The JVM property must appear **before** `-jar`.

The only debug-only UI function at present is **Export analysis PGN**. It becomes available after a completed game analysis and exports the engine diagnostics used to understand and regression-test CAT's annotations.

## First-time setup

### 1. Configure UCI engines

Open **Engine Settings**.

CAT separates an engine executable from a reusable engine profile:

- **Engines** registers executable UCI engines.
- **Profiles** combines one registered engine with concrete UCI option values.
- **Defaults** assigns profiles to White CPU, Black CPU, live evaluation, and deep analysis.

CAT can scan its configured discovery directory for Stockfish and Lc0. Other engines can be selected explicitly.

A practical engine installation should keep required companion files together with the executable. Lc0, for example, normally needs a neural-network weights file and may require platform-specific runtime libraries.

### 2. Create profiles

Create at least one profile for every engine/setup you want to use. A profile is the appropriate place for UCI options such as threads, hash size, neural-network-specific settings, or other engine options.

Profiles can then be reused without re-entering the engine options for every game or analysis.

### 3. Assign defaults

Under **Engine Settings → Defaults**, assign the desired profiles for:

- White CPU;
- Black CPU;
- live evaluation;
- deep analysis.

The analysis dialog still allows the analysis profile to be selected explicitly for each run.

## Using CAT

### Analyze a PGN game

1. Open **Data → Import New Game**.
2. Select a PGN containing exactly one game.
3. CAT opens the game and also stores it in the local database.
4. Click **Analyze**.
5. Select an engine profile.
6. Choose the search mode:
   - **Depth > 0**: analyze every position to the selected depth.
   - **Depth = 0**: use **Time per position** instead.
7. Start the analysis and wait for the complete game replay.
8. After completion, inspect the move list, annotations, engine variations, evaluation, and database continuations.

A running analysis can be cancelled. A completed analysis can be run again with different settings.

Selecting a move in a completed analysis opens the stored analysis for that position. Live evaluation can refine the currently selected historical move with the same annotation classifier used by the finite analysis.

When debug mode is enabled, **Export analysis PGN** becomes visible after the analysis finishes. Without debug mode this control is not rendered.

### Read move annotations

CAT uses four symbols:

| Symbol | Meaning |
| --- | --- |
| `??` | Blunder: at least 25 percentage points of practical winning chance lost relative to the best engine move. |
| `?` | Mistake: at least 10 percentage points of practical winning chance lost. |
| `!!` | Extraordinary move: objectively sound and backed by a concrete material-sacrifice or deep-discovery signal. |
| `!` | Critical, non-trivial best move with a large gap to the second-best candidate. |

The symbols are **not** a direct translation of centipawn loss, and `!!` is intentionally not defined as "the engine proved this move brilliant."

The design principle is:

> CAT marks a move `!!` only when it can name a concrete extraordinary property of an objectively sound move.

The full algorithm is summarized below and documented in detail in [DeepAnalysis move annotations](docs/deep-analysis-move-annotations.md).

### Play a game

Open **Data → New Game** and choose the clock settings.

CPU profile assignments come from **Engine Settings → Defaults**. The clock controls can be used to enable or disable computer play for White or Black. This allows human-vs-human, human-vs-engine, and engine-vs-engine use.

The evaluation bar can be enabled independently from the playing engines.

### Import and export the current game

The **Data** menu provides:

- **Export Current Game** — saves the currently represented game as PGN.
- **Import New Game** — accepts exactly one PGN game and opens it for analysis.
- **New Game** — starts a fresh game.
- **Terminate Program** — asks the backend to stop CAT and its managed UCI processes.

### Chess database

Open **Data → Chess Database** for the local PGN library.

The database workflow supports:

- importing PGN libraries containing one or many games;
- asynchronous import with progress and cancellation;
- searching stored games;
- opening stored games;
- querying position statistics and continuations.

Large PGN collections may take many minutes or several hours to import because CAT parses games, replays positions, checks duplicates, builds position statistics, and writes them to SQLite.

### Engine Manager

**Engine Manager** is different from **Engine Settings**.

- **Engine Settings** configures engine definitions, reusable profiles, options, and default assignments.
- **Engine Manager** shows current and historical UCI engine processes and their UCI communication and can terminate an engine process.

### Other controls

The header also provides:

- board orientation switching;
- language selection;
- access to analysis controls while an imported game is active.

## Move-annotation model

The annotation classifier is deterministic chess-domain logic in the `chess` module. It does not start an engine itself; it classifies the finite engine data it receives.

The decision order is:

```text
played move
    |
    +-- winning-chance loss >= 25? ----------------------> ??
    |
    +-- winning-chance loss >= 10? ----------------------> ?
    |
    +-- objectively sound + extraordinary evidence? ----> !!
    |
    +-- critical non-trivial final best move? ----------> !
    |
    +-- otherwise ---------------------------------------> no symbol
```

This ordering is important: a tactical idea or sacrifice cannot turn an objective mistake or blunder into `!!`.

### Practical winning chance

Engine scores are stored from White's point of view, then normalized to the player who made the move. Candidate moves are sorted from that mover's point of view.

For annotation thresholds, CAT converts the engine evaluation into a practical winning-chance percentage with the logistic mapping implemented by `EvaluationScoring`. This prevents very large centipawn swings in positions that are already overwhelmingly won from automatically looking like equally large practical errors.

### `?` and `??`

The loss is:

```text
winChanceLoss =
    winPercent(best candidate)
    - winPercent(played move)
```

Current thresholds:

- `?`: at least **10 percentage points**;
- `??`: at least **25 percentage points**.

These objective negative annotations are evaluated before any positive annotation.

### `!!`: extraordinary move

CAT no longer tries to infer an abstract notion of "brilliance." A `!!` must be objectively sound and must have one of two explainable properties.

Before either property can qualify, the move must:

- finish in the final **Top 3**;
- be within **10 percentage points** of the final best move;
- have at least three usable final candidates.

A material-sacrifice `!!` additionally requires that the final best line still gives the mover at least **15% practical winning chance**.

#### A. Material sacrifice

A material sacrifice must represent at least **3 points** of net material investment.

CAT recognizes three concrete shapes:

- **Active investment** — the piece moved by the candidate move is later captured in the engine PV.
- **New material offer** — the move newly exposes a different piece to a legal capture.
- **Declined material save** — a different piece was already threatened and could legally have escaped, but the candidate deliberately leaves it available.

The active detector follows the moved piece for up to **6 plies**. After its capture, one immediate recovery move is credited so that ordinary exchanges are not mistaken for sacrifices.

Passive offers are measured relative to the material balance **before** the root move and likewise credit an immediate legal recovery. A piece that was already unavoidably hanging does not earn sacrifice credit.

Kings are never sacrifice material. Promotions are excluded from moved-piece identity tracking.

Examples protected by regression tests include:

- Nezhmetdinov–Chernikov `12.Qxf6!!` — active net investment of 3.
- Byrne–Fischer `17...Be6!!` — declined material save / queen offer with net investment of 6.

#### B. Deep discovery

Deep discovery asks one narrow question:

> Did deeper search make the **played move itself** substantially stronger?

This deliberately avoids the former problem where a move looked special merely because its alternatives became worse faster.

Requirements:

- the move finishes at **rank 1**;
- early data is taken from **25–40% of that engine search's final depth**;
- at least **2** usable early snapshots are required;
- the median early regret must be at least **1 percentage point**;
- the move's own practical strength must increase by at least **20 percentage points** from the early median to the final result.

The depth window is relative rather than absolute. This matters because Stockfish and Lc0 have very different depth scales.

Kramnik–Leko `25...Qd3!!` is the key regression example: the move starts as a serious but not yet obvious candidate and becomes dramatically stronger with deeper search.

A move that merely rises in relative rank while its own evaluation deteriorates does **not** qualify.

### `!`: critical non-trivial best move

A `!` must be the final rank-1 move and lead rank 2 by at least **15 percentage points** of winning chance.

CAT suppresses `!` when the move was already trivially obvious early in the search:

- inspect the **30–50%** relative-depth window;
- require at least **2** usable snapshots before triviality can be established;
- an early snapshot is obvious when the move is already rank 1 and leads rank 2 by at least **10 percentage points**;
- if at least **70%** of the usable early snapshots are obvious, `!` is suppressed.

Because `!!` is evaluated before `!`, a best move that also has a qualifying extraordinary property receives `!!`.

### Regression protection

The general classifier rules are unit-tested with deterministic engine fixtures.

In addition, CAT has a **golden regression suite** built from the real Stockfish 19 / depth-15 diagnostic PGNs used while calibrating the current model. It protects critical classifications from:

- Kramnik–Leko;
- Nezhmetdinov–Chernikov;
- Byrne–Fischer.

These tests intentionally fail the build if a future algorithm change alters a protected result.

The test source contains an explicit warning: **do not simply update an expected value to make a failing build green.** First inspect the algorithm change, the chess position, and the original diagnostic engine values and decide explicitly whether the new classification is actually better.

See [DeepAnalysis move annotations](docs/deep-analysis-move-annotations.md) for the complete technical description and current golden cases.

## Project structure

The project is composed of several Git submodules:

- `chess` — chess rules, notation, game loading/saving, UCI integration, and annotation domain logic.
- `chess-database` — embedded SQLite chess database and PGN library importer.
- `chess-api` — Spring Boot REST backend and application services.
- `chess-frontend` — React/Vite browser frontend.
- `spring-annotation-context-initializer-template` — reusable Spring annotation-context initializer dependency.

## UCI engines

The application works with UCI-compatible chess engines such as Stockfish and Leela Chess Zero (Lc0).

### Engine download pages

The following engines are commonly used with CAT. Download the build that matches your operating system and CPU/GPU capabilities:

| Engine | Download page |
| --- | --- |
| Stockfish | [Official Stockfish downloads](https://stockfishchess.org/download/) |
| Leela Chess Zero (Lc0) | [Official Lc0 downloads](https://lczero.org/play/download/) |
| Dragon by Komodo | [Official Komodo/Dragon site](https://komodochess.com/) |
| Fire | [Fire releases on GitHub](https://github.com/FireFather/fire/releases/latest) |
| Reckless | [Reckless releases on GitHub](https://github.com/codedeliveryservice/Reckless/releases/latest) |

Dragon/Komodo is a legacy/commercial case: sales were discontinued in 2026. The official site remains the authoritative source for any still-available downloads or access for existing customers.

CAT does not bundle these engines. Each engine remains subject to its own license and distribution terms.

### Recommended locations

The conventional engine directory for this project is:

- Windows: `C:\\usr\\games`
- Unix/Linux: `/usr/games`

On Unix-like systems, `/usr/games` is also the application's default automatic discovery directory. Override it with:

```bash
java -Dchess.engine.discovery.directory=/path/to/engines -jar chess-api/target/chess-app.jar
```

Automatic discovery is deliberately conservative. Only executable files whose names contain `stockfish` or `lc0`, case-insensitively, are considered. A matching file must also start successfully and complete a UCI handshake.

Other UCI engines, and engines stored outside the discovery directory, can be added explicitly through **Engine Settings**.

### Engine configuration

Engine configuration is persisted by default in:

```text
~/.chess/engine-configs.json
```

Override it with:

```bash
java -Dchess.engine.config.file=/path/to/engine-configs.json -jar chess-api/target/chess-app.jar
```

## PGN and local database

There are two distinct PGN workflows:

- **Data → Import New Game** accepts exactly one game, opens it as the current analysis game, and stores it in the local database.
- **Data → Chess Database → Import PGN** accepts database libraries containing one or many games.

The embedded SQLite database is created by default at:

```text
~/.chess/database/chess.db
```

Override it with:

```bash
java -Dchess.database.path=/path/to/chess.db -jar chess-api/target/chess-app.jar
```

The backend currently permits multipart database uploads up to 20 GB. This is an upload limit, not a statement that such a collection can be imported quickly or with modest disk usage.

## Local application data

Unless overridden through system properties, persistent application data is stored below the current user's home directory:

```text
~/.chess/
├── engine-configs.json
└── database/
    └── chess.db
```

Backing up this directory preserves the local engine registry/profiles and chess database. Engine binaries themselves are not copied there.

## Frontend development

The production frontend is embedded in the Spring Boot JAR. For frontend development, Vite can be run separately:

```bash
cd chess-frontend
npm ci
npm run dev
```

Vite binds to `127.0.0.1` and proxies `/api` to the backend at `127.0.0.1:8080`. Start the backend separately before using API-dependent UI functions.

Available frontend scripts are:

```text
npm run dev
npm run build
npm run lint
npm run preview
```

## Continuous integration and releases

GitHub Actions validates the full Maven reactor, including all submodules and the frontend build.

Branch roles:

- `work` — active development branch.
- `master` — basis for releasable versions.

CI runs `mvn clean install` on pushes to `work` and `master`, pull requests targeting `master`, and manual workflow runs.

A release is created only by pushing a version tag such as `v0.1.0`. The release workflow verifies that the tagged commit belongs to `master`, runs the complete build and tests, and publishes:

- `cat-<tag>.jar`;
- `cat-<tag>.jar.sha256`.

Typical release sequence:

```bash
git checkout master
git pull
git tag v0.1.0
git push origin v0.1.0
```

Do not create release tags directly from `work`.

## Analysis design documentation

The detailed move-annotation design, architecture, thresholds, diagnostics, tests, and known limitations are documented in:

[docs/deep-analysis-move-annotations.md](docs/deep-analysis-move-annotations.md)

## Development status

This project is under active development. Analysis workflows, engine management, database features, localization, and frontend structure may evolve. The golden annotation tests are intentionally conservative: changes to protected move classifications should be treated as review events rather than routine expectation updates.
