# Browser evaluation fallback design

Status: **Draft**  
Scope: live evaluation only

## 1. Goal

CAT shall remain fully usable when no native UCI engine is installed. Live evaluation may then use a bundled, lightweight Stockfish Lite WebAssembly engine in the browser.

This is not a replacement for CAT's native engine architecture. Native engines remain the authoritative implementation for computer play, deep analysis and complete-game analysis.

The design must preserve CAT's module boundaries and avoid engine-specific branches in UI orchestration code.

## 2. Non-goals

The first implementation does not:

- run computer opponents in the browser;
- run deep analysis in the browser;
- register a browser engine as a native backend engine;
- emulate a filesystem engine path for WebAssembly;
- automatically start or download any engine when the application opens;
- silently convert unrelated backend failures into browser fallback.

## 3. Module responsibilities

### `chess`

Owns chess-domain behavior and the existing Java/native-UCI abstractions:

- `EvaluationEngine`;
- `PlayerEngine`;
- `DeepAnalysisEngine`;
- `EvaluationUciEngine`;
- `PlayerUciEngine`;
- `DeepAnalysisUciEngine`;
- UCI definitions, configuration and parsing needed by native engines.

The module must not know about browsers, Web Workers, HTTP or Stockfish Lite assets.

### `chess-api`

Owns application orchestration for native engines:

- discovery and registration of native UCI executables;
- engine profiles and assignments;
- runtime selection;
- native process lifecycle;
- REST/SSE exposure of native live evaluation;
- explicit reporting of native-engine availability.

The API must accept **no native engine configured** as a valid state.

### `chess-frontend`

Owns evaluation-source selection from the browser's point of view:

- backend live evaluation;
- browser live evaluation;
- lazy loading of Stockfish Lite;
- Web Worker lifecycle;
- browser-side UCI message parsing;
- presentation-independent conversion to the existing `EngineEvaluation` model.

React presentation code must not contain UCI parsing or Stockfish lifecycle logic.

### `chess-database`

No change. It has no responsibility for engines or evaluation runtime selection.

### `chess-project`

Owns assembly, release policy, submodule versions, project documentation and third-party distribution material.

Docker is not part of the product or release architecture.

## 4. Backend: make absence explicit

The current compatibility behavior that invents a fallback definition for `/usr/games/stockfish` must be removed.

A clean installation with no discovered or configured native engine shall be represented as:

```text
engines = []
profiles = []
fallbackProfileId = null

whitePlayerProfileId = null
blackPlayerProfileId = null
evaluationProfileId = null
deepAnalysisProfileId = null
```

No synthetic executable path shall be persisted.

### Runtime API

Runtime selection must distinguish an absent assignment from an invalid configuration. Methods that currently require a configuration should move toward explicit optional semantics, for example:

```java
Optional<UciEngineConfig> findEvaluationConfig();
Optional<UciEngineConfig> findWhitePlayerConfig();
Optional<UciEngineConfig> findBlackPlayerConfig();
```

The exact Java API may differ, but `null`/absence must be deliberate and never converted into a fake engine.

### Capability endpoint

The frontend should not infer runtime availability from profile-array contents. The backend shall expose explicit capabilities, conceptually:

```json
{
  "evaluation": { "configured": true, "available": true },
  "whitePlayer": { "configured": false, "available": false },
  "blackPlayer": { "configured": false, "available": false },
  "deepAnalysis": { "configured": true, "available": false }
}
```

`configured` and `available` are different. A saved executable may have been removed or may no longer start.

If an engine becomes unavailable between capability lookup and use, the evaluation endpoint shall return a defined availability error rather than leaking a `ProcessBuilder` exception.

## 5. Frontend abstraction

The frontend should introduce a source abstraction rather than another engine abstraction tied to one runtime:

```ts
interface LiveEvaluationSource {
  start(position: EvaluationPosition): Promise<void>;
  stop(): Promise<void>;
  dispose(): void;
  subscribe(listener: (evaluation: EngineEvaluation) => void): () => void;
}
```

Suggested structure:

```text
src/chess/evaluation/
    LiveEvaluationSource.ts
    LiveEvaluationController.ts
    BackendLiveEvaluationSource.ts
    BrowserLiveEvaluationSource.ts

src/chess/engine/browser/
    BrowserUciEngine.ts
    UciInfoParser.ts
    stockfish.worker.ts
```

### `BackendLiveEvaluationSource`

Encapsulates the existing transport details:

- `GET /api/eval`;
- `GET /api/eval/stream`;
- `POST /api/eval/stop`;
- polling/reconnect behavior.

`ChessBoard.tsx` must no longer know these protocol details.

### `BrowserLiveEvaluationSource`

Converts browser-UCI results into the already existing `EngineEvaluation` frontend model. It knows the browser engine adapter and parser, but not React presentation.

### `BrowserUciEngine`

Owns only Web Worker/UCI process semantics:

- create/terminate worker;
- `uci` / `isready`;
- `position`;
- `go infinite`;
- `stop`;
- message delivery.

It does not format evaluation bars, React state or engine-line UI.

### `UciInfoParser`

A pure, independently testable parser for UCI `info` lines:

- `depth`;
- `multipv`;
- `score cp`;
- `score mate`;
- `pv`.

It must not depend on Worker or React APIs.

## 6. Source selection

```text
User enables live evaluation
              |
              v
     LiveEvaluationController
              |
              v
 native backend evaluation available?
        /                 \
      yes                  no
       |                    |
       v                    v
 Backend source       Browser source
```

A defined `ENGINE_UNAVAILABLE` result from the backend may trigger the same fallback.

Other errors do not. HTTP failures, malformed responses and programming errors remain visible errors.

Source selection belongs to the controller/coordinator, not to either source implementation.

## 7. Startup and lazy loading

Application startup and a newly opened tab perform no evaluation work:

```text
page load
  -> no native evaluation process
  -> no browser worker
  -> no Stockfish Lite download
```

Only explicit user activation of live evaluation starts source selection.

Stockfish Lite is downloaded and instantiated only when the browser source is actually selected.

## 8. Stockfish Lite packaging

Use a single-threaded Stockfish Lite WebAssembly build to avoid introducing SharedArrayBuffer/COOP/COEP requirements in the first implementation.

Stockfish assets remain separate static third-party files and are not bundled into CAT's application JavaScript:

```text
chess-frontend/public/third-party/stockfish-lite/
    stockfish.js
    stockfish.wasm
    COPYING
    SOURCE.md
```

The exact upstream version and commit must be pinned.

The release process must additionally publish the corresponding source material for the distributed build from the same release location. A source archive is preferred over relying solely on an external upstream URL.

CAT source remains Apache-2.0. Stockfish/stockfish.js remains separately identified under GPLv3.

## 9. Engine settings and manager UI

The backend engine registry continues to contain native executable engines only.

Browser Stockfish may be presented as a built-in capability in the UI, but it must not receive:

- a backend engine id;
- a fake executable path;
- a backend UCI profile;
- persistence in `engine-configs.json`.

Native profile settings and browser fallback settings are separate concepts.

The first implementation should keep browser settings intentionally small. MultiPV may be fixed to the number needed by the existing live-evaluation UI unless a real user requirement justifies another browser-specific settings model.

## 10. Deep analysis and computer play

Without a native engine:

| Capability | First implementation |
| --- | --- |
| Live evaluation | Browser Stockfish Lite fallback |
| White/Black CPU | unavailable |
| Deep analysis | unavailable |
| Complete-game analysis | unavailable |

The UI must explain the unavailable native capabilities rather than failing when they are invoked.

A later browser-player implementation can reuse `BrowserUciEngine`, but it is explicitly outside this change.

## 11. Testing

### Backend

Tests must cover:

- startup with zero native engines;
- empty registry and null assignments;
- no synthetic `/usr/games/stockfish`;
- configured-but-missing engine;
- explicit availability response;
- defined unavailable-engine error;
- unchanged behavior with a valid UCI engine.

### Frontend

Introduce focused unit tests for the new non-React logic:

- UCI info parsing;
- MultiPV/depth snapshot selection;
- backend source selection;
- browser fallback selection;
- fallback after defined backend unavailability;
- no fallback for unrelated backend errors;
- stop/dispose semantics.

The browser worker receives an integration smoke test.

## 12. Implementation order

1. Make no-native-engine state valid in `chess-api`.
2. Introduce explicit backend engine capabilities.
3. Extract current frontend live-evaluation transport from `ChessBoard.tsx`.
4. Add source coordinator and tests.
5. Add browser UCI adapter/parser and Worker.
6. Add pinned Stockfish Lite assets and GPL source distribution.
7. Add UI status for browser/native evaluation source.
8. Run full regression suite and release-license verification.

The ordering intentionally establishes clean abstractions before adding Stockfish.
