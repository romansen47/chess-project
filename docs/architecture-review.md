# Architecture review

Date: 2026-10-30

Baseline: release `v0.3.0`

Status: current architecture and guardrails

## Dependency direction

The project keeps one acyclic dependency direction:

```text
spring-annotation-context-initializer-template
                |
                v
              chess
                |
        +-------+-------+
        |               |
        v               |
 chess-database         |
        |               |
        +-------+-------+
                v
            chess-api
                |
          REST / SSE
                |
                v
        chess-frontend
```

`chess-api` depends on both `chess` and `chess-database`.
`chess-database` depends only on `chess`. Domain and persistence modules never
depend on Spring controllers or React code.

## Responsibility map

### `chess`

Owns chess rules, notation, PGN replay, move annotations and reusable native
UCI protocol infrastructure. Move annotation decisions remain deterministic
domain logic and do not depend on REST DTOs.

Native and browser UCI implementations cannot share source code because they
run in different languages. They share transcript contracts under `contracts/`
for score, mate, MultiPV and malformed-output semantics.

### `chess-database`

Owns SQLite schema, PGN persistence, game search and position statistics. The
public `ChessDatabase` interface is the boundary used by the API application
layer. `SqliteChessDatabase` remains a facade over extracted import, query and
compatibility collaborators.

### `chess-api`

Owns application orchestration and native process lifecycle, not chess rules.
Important internal application boundaries are:

- `EngineSettingsService`: controller-compatible facade;
- `EngineSettingsRepository`: settings persistence port;
- `EngineSettingsRegistry`: definitions, profiles and validation;
- `EngineSettingsVersions`: runtime invalidation policy;
- `EngineRuntimeSelectionService`: session-only runtime overrides;
- `AnalysisReplayService`: replay session and cancellation coordinator;
- `AnalysisStepAnalyzer`: one engine analysis step;
- `AnalysisReplayPresenter`: API response construction;
- `ChessDatabaseService`: database workflow with injected database, executor,
  temporary-file and clock seams.

### `chess-frontend`

Owns browser state, presentation and browser Stockfish. `ChessBoard.tsx` is a
composition root rather than a feature implementation. Live-evaluation source
selection is isolated behind `LiveEvaluationController` and
`LiveEvaluationSource`.

Large views use controller hooks. `EngineProfileHierarchy.tsx`, for example,
contains presentation while `useEngineProfileHierarchyController` owns state
and server actions.

Translations are split by language and feature domain:

```text
translations/<language>/
    common.ts
    game.ts
    analysis.ts
    database.ts
    settings.ts
```

The language entry file composes these dictionaries. English remains the
canonical source of the `TranslationKey` type, and the i18n audit checks the
composed catalogs.

## Current orchestration sizes

Line count is only a warning signal, but the current split makes responsibility
changes visible:

| Component | Lines | Responsibility |
|---|---:|---|
| `ChessBoard.tsx` | 184 | frontend composition |
| `EngineProfileHierarchy.tsx` | 131 | engine-profile view |
| `useEngineProfileHierarchyController.ts` | 518 | engine-profile UI workflow |
| `EngineSettingsService.java` | 734 | settings facade and compatibility |
| `AnalysisReplayService.java` | 527 | replay session coordination |
| `ChessDatabaseService.java` | 440 | database application workflow |
| `SqliteChessDatabase.java` | 655 | database facade |

No translation domain file currently exceeds 12 KiB. The repository-wide
source guard still rejects Java, TypeScript, TSX and CSS files above 32 KiB.

## Testing strategy

### Domain tests

Chess rules and annotation policy use unit, golden and regression tests. Golden
tests protect behavior while detectors and policy objects remain independently
readable.

### Application-service tests

Application services must inject effects that otherwise make tests slow or
non-deterministic. This includes engine factories, repositories, executors,
temporary files and clocks. Tests cover lifecycle ordering, cancellation and
invariant repair rather than only controller status codes.

### Frontend orchestration tests

React hook tests cover cross-component ordering that pure helper tests cannot:

- disabling engines invalidates an outstanding computer move;
- a stale successful engine response reconciles instead of mutating the UI;
- game end stops evaluation and prevents another computer move;
- late evaluation errors are hidden after game end;
- a new game stops player, evaluation and analysis runtimes before replacement.

The CI coverage gate intentionally targets orchestration and live-evaluation
files rather than averaging the complete React presentation tree. The initial
minimums are 55% lines/statements, 60% functions and 45% branches. New tests
should raise these thresholds; adding untested code to the guarded files must
not lower them.

Java module-level JaCoCo thresholds remain a regression floor. Risky services
also require direct class tests because a module-wide percentage can hide an
untested coordinator.

## Cross-runtime and API contracts

Language-neutral fixtures under `contracts/` are read by Java and TypeScript
tests. They currently cover:

- UCI `info` parsing and white-perspective score normalization;
- mate-zero and bounded-score rejection;
- engine runtime assignment JSON.

Small HTTP contracts are validated at the frontend boundary. If the REST model
grows further, OpenAPI-generated TypeScript types may replace these focused
validators. Until then, every new cross-runtime DTO should have one shared
fixture or an explicit runtime parser.

## Build and packaging

The Spring Boot JAR remains the production artifact. `chess-api` builds and
embeds the sibling frontend. This is pragmatic but makes the API module depend
on the repository layout during packaging. A separate assembly module is only
justified when this causes a concrete build or release problem.

## Remaining watch points

1. `EngineSettingsService` still contains migration and fallback-repair flow.
   New settings behavior should go into existing collaborators rather than
   expanding the facade.
2. `AnalysisReplayService` still owns annotation deferral because it depends on
   adjacent replay plies. Extract it only when that policy changes or needs
   independent reuse.
3. `SqliteChessDatabase` can later delegate schema and position statistics to
   separate repositories while retaining `ChessDatabase` as its public facade.
4. Frontend runtime refs remain a deliberate composition mechanism. Lifecycle
   integration tests are mandatory before changing their wiring.
5. `SettingsManager.css` should be split by feature when its next functional
   change is made; CSS-only movement should not be mixed into engine behavior.

## Change rules

- Preserve the module dependency direction.
- Keep public facades stable while extracting collaborators.
- Add a test seam before adding asynchronous or destructive behavior.
- Prefer feature-aligned files over arbitrary size-based fragments.
- Keep UCI parsing and API DTO semantics synchronized through shared fixtures.
- Do not combine packaging redesign with feature work.
