# DeepAnalysis move annotations

CAT's move annotations are an experimental **DeepAnalysis-only** feature.
Live/infinite evaluation and normal engine play do not use this classifier.

The goal is not to copy one chess site's labels. CAT combines objective engine
quality with separate signals for moves that are unusually difficult or
interesting for a human to find.

## Symbols

- `!` — a critical, non-trivial best move.
- `!!` — an objectively sound move with strong human-difficulty evidence.
- `?` — an objective loss of at least 1.0 pawn relative to the best move.
- `??` — an objective loss of at least 3.0 pawns relative to the best move.

`!!` is not simply a stronger `!`. A brilliant move may finish at rank 2 or
3, while `!` requires the final best move.

## Architecture

The classification is chess-domain logic and lives in the `chess` module.

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
  1. objective quality
  2. human-difficulty evidence
  3. symbol selection
        |
        v
chess-api DTO mapping
        |
        v
chess-frontend display only
```

### Finite search result

`DeepAnalysisUciEngine.analyze(...)` returns one immutable
`DeepAnalysisResult` containing both final variants and intermediate depth
snapshots from the same search.

This replaced the former stateful combination of
`getBestLines(...)` plus `getLastDepthHistory()`.

### Classifier package

The classifier is in:

```text
demo.chess.analysis.annotation
```

Main responsibilities:

- `ObjectiveMoveQualityEvaluator` — classifies the final engine loss as
  acceptable, mistake, or blunder.
- `MoveAnnotationClassifier` — orchestrates the three classification layers
  and selects the visible symbol.
- `MoveAnnotationPolicy` — central numeric thresholds.
- `EvaluationScoring` — mover-centric score normalization, winning chances,
  MultiPV sorting, and root-move matching.
- `OnlyMoveDetector` — triviality filter for `!`.
- `BrilliantMoveDetector` — combines independent `!!` signals.
- `MaterialInvestmentDetector` — verifies that a material sacrifice is tied
  to the piece moved by the candidate root move.

The API only maps the domain result to DTOs. The frontend only renders badges
and localized tooltips.

## Score normalization

Engine evaluations are stored from White's point of view.

For candidate ranking:

- White move: higher evaluation is better.
- Black move: lower White-centric evaluation is better.

CAT never trusts MultiPV emission order as quality ranking; candidates are
sorted by normalized mover score.

For practical thresholds CAT maps evaluation to winning chance using the
logistic mapping in `EvaluationScoring`.

## Three-layer classification model

### Layer 1: objective quality

The final loss relative to the best engine candidate is calculated first.

Current thresholds:

- loss < 1.0 pawn: objectively acceptable for annotation purposes;
- loss >= 1.0 pawn: `?`;
- loss >= 3.0 pawns: `??`.

This layer has priority over human-interest signals. A sacrifice or surprising
idea does **not** turn an objective mistake/blunder into `!!`.

When the played move is absent from final MultiPV, CAT falls back to the
resulting-position evaluation from the following replay point. This compares
two searches and remains a known approximation.

### Layer 2: human-difficulty evidence

Only objectively acceptable moves can be considered for positive annotations.

#### `!`: critical but non-trivial best move

The played move must be final rank 1.

Final criticality requires:

- at least two usable candidates;
- a winning-chance gap of at least **15 percentage points** between rank 1 and
  rank 2.

A triviality filter then inspects the early search window from **30% to 50% of
final depth**.

An early snapshot counts as obvious when the played move is already rank 1 and
leads rank 2 by at least **10 percentage points**. If at least **70%** of usable
snapshots in that window are obvious, `!` is suppressed. At least two usable
snapshots are required before suppression.

This is intended to reject obvious forced recaptures and similar moves.

#### `!!`: objective soundness plus brilliance evidence

The played move must:

- finish in the final **Top 3**;
- already have passed the objective-quality layer;
- be within **10 percentage points of practical winning chance** of the final
  best move.

It then needs at least one of the following independent signals.

##### Signal A: deep discovery by regret reduction

A rank change by itself is **not** evidence of brilliance. Opening moves can
move from rank 4 to rank 2 while all candidate evaluations remain virtually
identical.

Instead CAT measures **regret**:

```text
regret = winning chance(best move) - winning chance(played move)
```

At approximately **60% of final depth**:

- early regret must be at least **12 percentage points**;
- regret must improve by at least **10 percentage points** by final depth.

If the played move is outside the available early MultiPV set, the worst
returned candidate is used as a conservative upper bound for the move's early
score. This yields a lower bound on regret without treating absence/rank alone
as brilliance.

Late stability is also required: starting around **75% of final depth**, the
move must remain Top 3 in at least two of the last three usable snapshots.

##### Signal B: causal material investment

Material values are:

- pawn = 1
- knight = 3
- bishop = 3
- rook = 5
- queen = 9
- king = 0

The previous prototype looked for the worst material balance anywhere in the
next six plies. That was too broad: an unrelated later exchange could make the
root move look brilliant.

The current detector instead tracks the **piece moved by the candidate root
move**. That exact piece must be captured within the six-ply horizon. Only then
can the move have a material-investment signal.

After the tracked piece is captured, CAT allows the sacrificing side one
immediate reply to recover material. This prevents ordinary exchanges from
being interpreted as sacrifices. Additional unrelated loss on that reply is not
charged to the original move.

The remaining material deficit relative to the root position must be at least
**2 points**.

Examples the model is intended to distinguish:

```text
Qxf6  ...gxf6       -> possible material-investment signal
Bxc6  ...dxc6       -> ordinary equal exchange, no signal
e4 ... later Q loss -> no signal for e4 because the e-pawn was not sacrificed
```

Promotions are excluded from this identity-based detector because the pawn
object is replaced by the promoted piece.

### Layer 3: symbol selection

For one move only one symbol is shown.

Current selection order is:

1. objective blunder -> `??`
2. objective mistake -> `?`
3. objectively acceptable + brilliance evidence -> `!!`
4. critical non-trivial final best move -> `!`
5. otherwise no annotation

This means `!!` can override `!`, but can no longer override `?` or `??`.

## Testing strategy

The annotation tests have **no real engine dependency**.

```text
chess/src/test/java/demo/chess/analysis/annotation/
    MoveAnnotationClassifierTest.java
```

Tests build synthetic `EngineLine` and `DeepAnalysisResult` fixtures. CAT's
own board model is used only when a PV must be replayed for material-sacrifice
detection. No Stockfish or Lc0 process is started.

Current regression coverage includes:

- obvious early best move -> no `!`;
- critical non-trivial best move -> `!`;
- shuffled MultiPV input order does not affect ranking;
- close opening rank movement -> no deep-discovery `!!`;
- large regret reduction with late stability -> `!!`;
- sound queen sacrifice -> material `!!`;
- objectively bad queen sacrifice -> remains `??`;
- unrelated later material loss -> does not make the root move brilliant;
- ordinary equal exchange -> no material `!!`;
- normal development -> no material `!!`;
- Black score normalization;
- `?` and `??` thresholds.

Real games that expose false positives or negatives should become new synthetic
regression fixtures before thresholds are changed.

## Known limitations

### First move

The initial replay point is still a fixed +0.30 without an engine search.
Therefore move 1 cannot currently receive an annotation.

### MultiPV availability

Positive annotations require enough usable candidate lines. Time-based searches
may finish with fewer complete variants than requested.

### Mate scores

Mate values are represented by large numeric evaluation values. Annotation
thresholds are not yet explicitly mate-aware.

### Engine-specific depth

Depth values are only compared within one search by the same engine. Depth 20
from one engine is not assumed equivalent to depth 20 from another.

### Material model

The material signal is intentionally narrow. It does not attempt to understand
all tactical motifs, long forced sacrifice chains, piece-square value, king
safety, or positional compensation. Those remain part of the engine evaluation.

The six-ply identity-tracking horizon is a heuristic and may miss a delayed
sacrifice whose offered piece is accepted later.

### Standard-start replay

Material replay currently reconstructs positions from the standard starting
position and move history. Arbitrary FEN roots and future Chess960 support will
need corresponding replay support.

## Tuning policy

All numeric thresholds belong in:

```text
chess/src/main/java/demo/chess/analysis/annotation/MoveAnnotationPolicy.java
```

Do not scatter tuning constants through detector implementations. Prefer real
game examples plus deterministic regression fixtures for each semantic change.

The annotations remain an experimental model of engine quality plus human
difficulty, not an objective definition of chess punctuation.
