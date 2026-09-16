# Architecture review

Date: 2026-09-16  
Status: current-state review

## 1. Dependency structure

The current project has a clear, acyclic dependency direction:

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

More precisely, `chess-api` depends directly on both `chess` and `chess-database`, while `chess-database` depends on `chess`.

This is a good foundation. There are no reverse dependencies from domain/database modules into the API or frontend.

## 2. Strong boundaries already present

### Chess domain and analysis

Chess rules, notation, PGN handling and move-annotation logic live in `chess`. In particular, the annotation classifier does not depend on REST or React. This is the correct location for deterministic chess-domain behavior.

### Database

`chess-database` owns SQLite persistence, PGN-library storage and position statistics. It depends on the chess model rather than reimplementing chess rules.

### Application layer

`chess-api` performs orchestration: game lifecycle, engine runtime selection, analysis workflows, database application services and REST exposure.

### Browser UI

`chess-frontend` consumes the backend as an application API and already contains an incremental feature-oriented extraction under `src/chess/`.

These boundaries should be preserved.

## 3. Main architectural hotspots

The dominant risks are large classes/components, not module cycles.

### `ChessBoard.tsx`

Current size: about 2,579 lines, 85 named functions and a large number of React hooks.

It still coordinates board state, game lifecycle, import/replay, live evaluation, analysis evaluation and significant presentation state.

The existing `src/chess/README.md` already defines an incremental extraction strategy. That strategy is correct and should continue.

**Rule for the browser-engine work:** no new UCI, Worker, polling or fallback logic should be added directly to `ChessBoard.tsx`. Live-evaluation orchestration should be extracted first.

### `EngineConfigManager.tsx`

Current size: about 1,454 lines.

It combines default assignments, profile CRUD, engine CRUD, engine inspection/discovery and most of their presentation.

This is manageable today but already beyond a comfortable single-component responsibility. A later extraction into Defaults/Profile/Engine panels plus a shared state/controller layer would reduce risk. It is not required to implement the browser fallback because browser Stockfish must not be inserted into this native registry.

### `EngineSettingsService`

Current size: about 1,391 lines and roughly 68 methods.

It currently handles several responsibilities:

- engine registry;
- profile registry;
- defaults/fallback assignment;
- persistence;
- legacy migration;
- system discovery integration;
- DTO conversion;
- validation.

This is the most important backend structural hotspot for the proposed work.

A clean evolution is to keep `EngineSettingsService` as a facade for existing controllers while delegating internally to narrower collaborators, for example:

```text
EngineSettingsService (facade)
    |
    +-- EngineConfigurationRepository
    |      persistence + migration
    |
    +-- EngineRegistry
    |      definitions + profiles
    |
    +-- EngineAssignmentService
    |      persistent defaults
    |
    +-- EngineDiscoveryService
           native discovery
```

Runtime overrides remain in `EngineRuntimeSelectionService`.

An `EngineAvailabilityService` should own executable/liveness capability checks instead of adding them to the already large settings service.

This split can be introduced incrementally and does not require changing the public REST contract in the same step.

### `SqliteChessDatabase`

Current size: about 1,555 lines and roughly 50 methods.

The module boundary itself is good, but the implementation class contains a large amount of schema, transaction, import, query and statistics behavior.

This is independent of the browser-engine work. It is a medium-priority refactoring candidate, not something to combine with the engine change. Future internal components could separate schema/migration, game repository, position-statistics repository and import transactions while keeping `ChessDatabase` as the public facade.

## 4. `chess`: domain plus native UCI infrastructure

The `chess` module intentionally contains both chess-domain code and native-UCI integration.

That is acceptable at the current project size because UCI integration is a core capability and is already hidden behind interfaces such as `EvaluationEngine`, `PlayerEngine` and `DeepAnalysisEngine`.

A future split into `chess-core` and `chess-uci` is only justified if engine infrastructure grows substantially. Creating another module solely for the browser fallback would make the architecture worse: browser concerns belong to the frontend.

The browser implementation should mirror the **concept** of the existing engine abstraction without attempting to share a Java interface across runtime boundaries.

## 5. Build and packaging boundary

The production artifact is the Spring Boot JAR. `chess-api` currently invokes the sibling frontend's npm build and embeds `chess-frontend/dist`.

This is pragmatic for a local desktop-like web application, but it means `chess-api` is not fully build-independent from the repository layout.

Longer term, the cleaner model would be a dedicated application/assembly responsibility at the root or in a packaging module:

```text
chess-api        -> backend artifact
chess-frontend   -> frontend artifact
chess-app        -> assembles both
```

This is not required now and should not be mixed into the browser-engine change unless packaging starts causing concrete problems.

Docker has no role in this model and is removed from the repository.

## 6. Local-application assumption

`NativeEngineFilePickerService` and native executable management assume that browser and backend represent one local application environment.

That is consistent with CAT's current product definition. It should remain an explicit architectural assumption because a future remote/server deployment would require a different engine-file selection and trust model.

## 7. API model duplication

Java DTOs and TypeScript frontend interfaces are maintained manually. This is simple and currently workable, but schema drift is possible.

If the API surface continues to grow, generating TypeScript types from an OpenAPI contract would improve consistency. It is not needed for the browser fallback if the new capability DTO remains small and tested on both sides.

## 8. Frontend testing gap

The frontend currently has build and lint scripts but no focused unit-test script.

The browser-engine work introduces pure logic with meaningful failure modes, especially UCI parsing and source selection. This is a good point to introduce Vitest for small, deterministic frontend tests without trying to retrofit the entire UI at once.

## 9. Repository hygiene

The `chess` repository currently contains `default.profraw`, a profiling output artifact. It is not an architectural component and should be removed in a separate conservative cleanup.

Several module READMEs also contain version statements that have drifted from their POMs. Documentation version facts should be corrected separately rather than coupled to functional engine work.

## 10. Architectural conclusion

The module decomposition is fundamentally sound and should **not** be redesigned for Stockfish Lite.

The browser fallback should instead reinforce existing boundaries:

```text
chess
  native chess/UCI abstractions

chess-api
  native engine availability + application orchestration

chess-frontend
  evaluation-source selection + browser engine runtime

chess-database
  persistence only

chess-project
  assembly + release + licensing
```

The recommended structural work before adding Stockfish Lite is deliberately narrow:

1. remove the fake native-engine fallback;
2. extract live-evaluation transport/orchestration from `ChessBoard.tsx`;
3. keep `EngineSettingsService` as a facade but move new availability responsibility into a dedicated service;
4. add focused frontend tests;
5. only then introduce the Web Worker/WASM implementation.

This improves the architecture rather than merely accommodating a new engine.
