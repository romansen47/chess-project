# DeepAnalysis move annotations

This document describes CAT's experimental move-quality annotations shown after
moves in the move list.

The annotations are deliberately a **DeepAnalysis-only** feature. Live/infinite
evaluation, normal engine play, and other engine consumers do not use this
classification logic.

## Goals

CAT does not try to copy one existing chess site's move labels. The goal is to
combine objective engine information with signals that make a move interesting
from a human point of view.

The current symbols have different meanings:

- `!` — a critical, non-trivial best move.
- `!!` — a strong move that appears unusually difficult or remarkable for a
  human to find.
- `?` — a substantial objective loss compared with the best move.
- `??` — a very large objective loss compared with the best move.

`!!` is intentionally **not** a stronger form of `!`. A brilliant move does
not have to be the engine's number-one move. It only has to finish inside the
configured final Top-N set, currently Top 3, and satisfy at least one brilliance
signal.

## Architecture

The classification is domain logic and therefore lives in the **`chess`
module**, not in the React frontend.

The intended dependency direction is:

```text
DeepAnalysisUciEngine
        |
        v
DeepAnalysisResult
  - finalLines
  - depthHistory
        |
        v
MoveAnnotationClassifier
        |
        v
chess-api DTO mapping
        |
        v
chess-frontend display only
```

### `chess`: finite search result

`DeepAnalysisUciEngine` performs the finite UCI search used by DeepAnalysis.

During one search the engine receives UCI lines such as:

```text
info depth 10 multipv 1 score cp 35 pv ...
info depth 10 multipv 2 score cp 10 pv ...
```

Intermediate usable depth snapshots and the final variants are returned
together in one immutable `DeepAnalysisResult`:

```java
DeepAnalysisResult
    finalLines
    depthHistory
```

This replaces the former two-step contract:

```text
getBestLines(...)
getLastDepthHistory()
```

That old design was stateful: the caller had to assume that "last history"
still belonged to the preceding `getBestLines` invocation.
`DeepAnalysisResult` makes that relationship explicit and atomic.

The compatibility method `getBestLines(...)` remains because
`DeepAnalysisEngine` also implements the general `EvaluationEngine`
contract. DeepAnalysis consumers themselves use `analyze(...)`.

Live/infinite evaluation does not produce a `DeepAnalysisResult` and does not
run the annotation classifier.

### `chess`: classification

The classifier is located below:

```text
demo.chess.analysis.annotation
```

Responsibilities are separated into small classes:

- `MoveAnnotationClassifier` — annotation precedence and orchestration.
- `MoveAnnotationPolicy` — all heuristic thresholds.
- `EvaluationScoring` — mover-centric score normalization, winning chances,
  MultiPV sorting, and root-move matching.
- `OnlyMoveDetector` — the triviality filter for `!`.
- `BrilliantMoveDetector` — combines independent `!!` signals.
- `MaterialInvestmentDetector` — replays a final PV and measures temporary
  material drawdown.
- `MoveAnnotation` — domain result.
- `DeepAnalysisResult` — engine-search result consumed by the classifier.

New annotation heuristics belong in this domain package. They should not be
implemented in the API or frontend.

### `chess-api`: orchestration and DTO mapping

`AnalysisReplayService` owns the complete-game DeepAnalysis replay.

For move N, the service keeps the `DeepAnalysisResult` of the position before
that move. After move N has been played and the resulting position has been
evaluated, it calls the core classifier with:

- the position before the move;
- the played UCI move;
- the previous position's `DeepAnalysisResult`;
- the evaluation of the resulting position as a fallback when the played move
  was not present in final MultiPV.

The resulting domain `MoveAnnotation` is converted to `MoveAnnotationDto` and
attached directly to the corresponding `AnalysisProfilePointDto`.

Intermediate depth history is no longer serialized to the browser.

### `chess-frontend`: display only

The frontend does **not** calculate move quality.

`AnalysisProfilePoint.annotation` already contains the result calculated by
the core. The frontend only:

- indexes annotations by ply;
- renders the badge after SAN;
- formats localized tooltips.

The former frontend files containing heuristic logic
(`moveAnnotationPolicy.ts`, `brilliantMoveDetection.ts`,
`onlyMoveDetection.ts`, and scoring helpers) have been removed.

This boundary is important for future consumers such as PGN annotation: they
can reuse the same core classifier without reproducing browser logic.

## Engine-score normalization

Engine evaluations are stored from White's point of view.

For ranking candidate moves, the score is converted to the point of view of the
player who made the move:

- White move: higher evaluation is better.
- Black move: lower White-centric evaluation is better.

CAT never assumes that an engine's MultiPV number is a quality ranking. The
received candidate lines are sorted independently by normalized mover score.
This is important because engines may emit MultiPV lines in different orders.

For some thresholds CAT maps centipawn evaluations to practical winning
chances using the current logistic mapping in `EvaluationScoring`. This avoids
treating the same raw pawn difference identically near equality and in an
already overwhelming position.

## Annotation precedence

For one move, only one symbol is displayed.

Current precedence:

1. `!!`
2. `??`
3. `?`
4. `!`
5. no annotation

The high priority of `!!` is intentional. A humanly remarkable move may be
materially speculative or may evaluate below another engine line while still
meeting one of CAT's brilliance criteria.

## `!`: critical but non-trivial best move

A move is considered for `!` only when it is the final best move.

### Final criticality

At the final DeepAnalysis depth:

- the played move must be rank 1;
- at least two usable candidates must exist;
- the winning-chance gap between rank 1 and rank 2 must be at least **15
  percentage points**.

### Triviality filter

A move that is obvious very early in the search should not receive `!` merely
because every alternative is terrible.

The early window is currently **30% through 50% of final search depth**.

An early snapshot counts as obvious when:

- the played move is already rank 1; and
- its winning-chance lead over rank 2 is at least **10 percentage points**.

If at least **70%** of usable snapshots in the early window are obvious, the
move is treated as trivial and `!` is suppressed. At least two usable early
snapshots are required before CAT suppresses the annotation.

This is intended to reject cases such as an obvious pawn recapture after a
piece exchange.

## `!!`: brilliant move

The played move must finish inside the final **Top 3**. It does not need to be
rank 1 and it is not required to satisfy the `!` rule.

A move receives `!!` when at least one of the following independent signals
is present.

### Signal A: deep discovery

This signal asks whether the same engine needed substantial search depth to
appreciate the move.

Current prototype:

- final rank is Top 3;
- at approximately **60% of final depth**, the move was either outside Top 3
  or its winning chance later improved by at least **15 percentage points**;
- late stability is required: in at least two of the last three sufficiently
  deep snapshots, starting around **75% of final depth**, the move must remain
  Top 3.

This catches moves whose strength only becomes visible after deeper search.

### Signal B: material investment

This signal detects humanly difficult sacrifices whose positional compensation
may hide the material cost in the engine evaluation.

Material values are currently:

- pawn = 1
- knight = 3
- bishop = 3
- rook = 5
- queen = 9
- king = 0

For the final PV of the played Top-3 move, CAT reconstructs the position in the
core and compares the mover's material balance with the root position. It finds
the largest drawdown during the first **6 plies** of the PV.

If that drawdown is at least **2 material points**, the move has a material
investment signal.

The limited six-ply horizon is intentional. Without a horizon, an unrelated
sacrifice much later in a long PV could incorrectly make the original move look
brilliant.

The calculation uses the minimum material balance along the PV rather than only
the board directly after the played move. This catches sacrifices where, for
example, a queen is offered on the played move and accepted on the opponent's
reply.

The material does **not** have to be won back later. A permanent exchange of
material for initiative, king safety, passed pawns, or other positional
compensation may still be a brilliance signal.

### Multiple brilliance signals

If both deep discovery and material investment are present, the move still gets
one `!!`, while the tooltip reports both reasons.

## `?` and `??`

These labels use the loss from the best final candidate from the mover's point
of view:

- `?` at **1.0 pawn** loss or more;
- `??` at **3.0 pawns** loss or more.

When the played move itself is absent from final MultiPV, CAT falls back to the
evaluation of the resulting position. This compares data from two consecutive
searches and is therefore less pure than comparing candidates from one root
search. It is retained for the current prototype and should be revisited if a
better root-move evaluation becomes available.

## Testing strategy

Annotation tests deliberately have **no real chess-engine dependency**.

The main regression suite is:

```text
chess/src/test/java/demo/chess/analysis/annotation/
    MoveAnnotationClassifierTest.java
```

Tests construct synthetic `EngineLine` objects and synthetic
`DeepAnalysisResult` depth histories. The only real chess functionality used
is CAT's own board model and legal-move resolver when a PV has to be replayed
for material-investment detection.

No Stockfish or Lc0 executable is started. No engine binary is required on the
test machine. The tests are therefore deterministic and suitable for the
normal Maven unit-test phase.

Current covered behaviors include:

- an obvious early best move is filtered out instead of receiving `!`;
- a critical but non-trivial best move receives `!`;
- MultiPV input order does not define candidate ranking;
- a move discovered only at deeper search receives `!!`;
- a temporary queen investment can receive `!!` even when its numerical
  engine loss would otherwise qualify as `??`, verifying annotation
  precedence;
- ordinary development is not mistaken for a material sacrifice;
- Black evaluations are ranked from Black's point of view.

Future regression fixtures should be added whenever a real analyzed game causes
a threshold or semantic rule to change.

## Known limitations

### First move of a game

The initial profile point is currently fixed to +0.30 and contains no engine
search result. Therefore the first move cannot receive these annotations yet.

### MultiPV availability

Positive labels need enough candidate lines. A time-based search may return
fewer usable MultiPV lines than configured.

### Mate scores

Mate values are represented by large numeric evaluation values in the existing
engine pipeline. Annotation thresholds are not yet explicitly mate-aware.

### Engine depth is engine-specific

Depth 20 in Stockfish is not equivalent to depth 20 in Lc0. The deep-discovery
heuristic only compares intermediate depths **within the same search by the same
engine**. It must not be interpreted as a cross-engine depth scale.

### Material heuristic

The material model is intentionally simple and ignores piece-square value,
bishop pair, pawn structure, king safety, and other positional concepts. Those
concepts remain in the engine evaluation. Material is used only as an
additional human-difficulty signal.

The material replay currently assumes the same standard-start move history used
by the DeepAnalysis UCI command. If DeepAnalysis later gains arbitrary FEN or
Chess960 roots, both engine positioning and material replay must evolve
together.

## Tuning policy

All numeric thresholds belong in:

```text
chess/src/main/java/demo/chess/analysis/annotation/MoveAnnotationPolicy.java
```

When tuning the system, change policy values rather than scattering numbers
through detector implementations. Prefer testing against known games and add a
regression fixture for every threshold change motivated by a concrete example.

The current rules are an experimental model, not a claim that `!` or `!!`
can be determined objectively from engine output alone.
