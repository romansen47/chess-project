# DeepAnalysis move annotations

This document describes CAT's experimental move-quality annotations shown after
moves in the move list.

The annotations are deliberately a **DeepAnalysis-only** feature. Live/infinite
evaluation, normal engine play, and other engine consumers must not use this
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

## Data flow and architectural boundary

The feature currently spans three layers, but each layer has one specific
responsibility.

### chess

`DeepAnalysisUciEngine` performs the finite UCI search used by DeepAnalysis.

The engine already receives `info depth ... multipv ... pv ...` lines while the
search is running. For DeepAnalysis it now preserves completed intermediate
depth snapshots instead of discarding all information below the final depth.

The normal live/infinite evaluation implementation is not changed by this
history collection.

### chess-api

`AnalysisReplayService` owns the complete-game DeepAnalysis replay.

For each analyzed position it returns:

- the final engine lines,
- the final evaluation and depth,
- compact intermediate depth snapshots.

Intermediate snapshots contain only what the annotation algorithm needs:
depth, candidate evaluation, and the board position after the candidate's first
move. Full PVs are not duplicated for every intermediate depth.

The final engine lines still contain their board positions along the PV. Those
positions are used for material-investment detection.

### chess-frontend

The frontend classifies the already-produced DeepAnalysis data. The code is
split by responsibility:

- `moveAnnotationPolicy.ts` — all heuristic thresholds.
- `moveAnnotationScoring.ts` — score normalization, sorting, winning chances,
  and material arithmetic.
- `onlyMoveDetection.ts` — triviality filter for `!`.
- `brilliantMoveDetection.ts` — independent brilliance signals for `!!`.
- `moveAnnotationModel.ts` — annotation result types.
- `moveAnnotations.ts` — orchestration and precedence only.

This separation is intentional. New heuristics should normally be implemented
inside a detector or scoring helper rather than added directly to the
orchestrator.

## Engine-score normalization

Engine evaluations are stored from White's point of view.

For ranking candidate moves, the score is converted to the point of view of the
player who made the move:

- White move: higher evaluation is better.
- Black move: lower White-centric evaluation is better.

CAT never assumes that an engine's MultiPV number is a quality ranking. The
received candidate lines are sorted independently by the normalized mover
score. This is important for engines that emit MultiPV lines in a different
order.

For some thresholds CAT maps centipawn evaluations to practical winning
chances with the same logistic form used by the existing annotation prototype.
This avoids treating a two-pawn difference near equality exactly like a
two-pawn difference in an already overwhelming position.

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

A move is first considered for `!` only when it is the final best move.

### Final criticality

At the final DeepAnalysis depth:

- the played move must be rank 1;
- at least two usable candidates must exist;
- the winning-chance gap between rank 1 and rank 2 must be at least **15
  percentage points**.

### Triviality filter

A move that is obvious very early in the search should not receive `!` merely
because every alternative is terrible.

The early window is currently **30% through 50% of the final search depth**.

An early snapshot counts as "obvious" when:

- the played move is already rank 1; and
- its winning-chance lead over rank 2 is at least **10 percentage points**.

If at least **70%** of usable snapshots in the early window are obvious, the
move is treated as trivial and `!` is suppressed. At least two usable early
snapshots are required before CAT suppresses an annotation.

This is designed to reject cases such as an obvious pawn recapture after a
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

This signal detects humanly difficult sacrifices that may not look dramatic in
the final engine evaluation because positional compensation is already included
in that evaluation.

Material values are currently:

- pawn = 1
- knight = 3
- bishop = 3
- rook = 5
- queen = 9
- king = 0

For the final PV of the played Top-3 move, CAT compares the mover's material
balance with the root position and finds the largest material drawdown during
the first **6 plies** of the PV.

If that drawdown is at least **2 material points**, the move has a material
investment signal.

The limited six-ply horizon is intentional. Without a horizon, an unrelated
sacrifice much later in a long PV could incorrectly make the original move look
brilliant.

The calculation uses the minimum material balance along the PV rather than only
the board directly after the played move. This is essential for sacrifices such
as a queen offer that is accepted on the opponent's reply.

The material does **not** have to be won back later. A permanent exchange of
material for initiative, king safety, passed pawns, or other positional
compensation may still be a brilliance signal.

### Multiple brilliance signals

If both deep discovery and material investment are present, the move still gets
one `!!`, while the tooltip reports both reasons.

## `?` and `??`

These labels currently use the loss from the best final candidate from the
mover's point of view:

- `?` at **1.0 pawn** loss or more;
- `??` at **3.0 pawns** loss or more.

When the played move itself is not present in the final MultiPV candidates, CAT
falls back to the evaluation of the resulting position from the next
DeepAnalysis point. This mixes two separate searches and is therefore less
clean than comparing lines from one root position. It is accepted for the
current prototype but should be revisited.

## Known limitations

### First move of a game

The initial profile point is currently fixed to +0.30 and contains no engine
lines. Therefore the first move cannot receive these annotations yet.

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

### No automated heuristic test suite yet

The frontend currently has no dedicated unit-test runner for these rules. This
is the biggest maintainability gap in the annotation subsystem. Before the
heuristics become stable or are persisted into PGN, representative position
fixtures should be added for:

- obvious recaptures that must not receive `!`;
- known only moves that should receive `!`;
- deep-discovery combinations that should receive `!!`;
- material sacrifices that should receive `!!`;
- false-positive sacrifices and ordinary exchanges;
- White and Black score normalization;
- MultiPV order independence.

## Tuning policy

All numeric thresholds belong in
`chess-frontend/src/chess/analysis/moveAnnotationPolicy.ts`.

When tuning the system, change the policy values rather than scattering numbers
through detector implementations. Prefer testing against known games and
document the examples that motivated a threshold change.

The current rules are an experimental first model, not a claim that `!` or
`!!` can be determined objectively from engine output alone.
