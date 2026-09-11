# DeepAnalysis move annotations

CAT's move annotations are an experimental **DeepAnalysis-only** feature.
Live/infinite evaluation and normal engine play do not use this classifier.

The goal is not to copy one chess site's labels. CAT combines objective engine
quality with separate signals for moves that are unusually difficult or
interesting for a human to find.

## Symbols

- `!` — a critical, non-trivial best move.
- `!!` — an objectively sound move with strong human-difficulty evidence.
- `?` — a practical winning-chance loss of at least 10 percentage points relative to the best move.
- `??` — a practical winning-chance loss of at least 25 percentage points relative to the best move.

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

The final practical winning-chance loss relative to the best engine candidate
is calculated first:

```text
winChanceLoss =
    winPercent(best move)
    - winPercent(played move)
```

Current thresholds:

- loss < 10 percentage points: objectively acceptable for annotation purposes;
- loss >= 10 percentage points: `?`;
- loss >= 25 percentage points: `??`.

The raw pawn-evaluation difference is deliberately not used for these symbols.
Near equality, the new thresholds remain close to the old 1-pawn / 3-pawn
semantics. In a position that is already overwhelmingly won, however, a change
such as +17.77 to +12.82 represents less than one percentage point of practical
winning chance and therefore does not become `??`.

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

##### Deep discovery: relative search phases

Deep discovery deliberately uses **relative** phases of the engine's own search
rather than absolute depth numbers. This matters because a depth value from
Stockfish is not directly comparable with a depth value from Lc0.

The current phases are:

```text
early   25-40% of final depth
middle  45-65% of final depth
late    75-100% of final depth
```

At least two usable snapshots are required in every phase. Phase measurements
use medians, so one volatile depth does not create a brilliant annotation by
itself.

A deep-discovery `!!` can be produced by either of two independent patterns.

###### Signal A: rank/regret discovery

A rank change by itself is **not** evidence of brilliance. Opening moves can
move from rank 4 to rank 2 while all candidate evaluations remain virtually
identical.

Instead CAT measures **regret**:

```text
regret = winning chance(best move) - winning chance(played move)
```

For rank/regret discovery:

- median early regret must be at least **12 percentage points**;
- total regret improvement from early to late must be at least
  **10 percentage points**;
- regret must improve by at least **3 percentage points** from early to middle;
- regret must improve by at least **3 percentage points** from middle to late;
- in the late phase the move must remain Top 3 in at least two of the last
  three usable snapshots.

If the played move is outside the available MultiPV set in a snapshot, the
worst returned candidate is used as a conservative upper bound for the move's
score. This yields a lower bound on regret without treating absence/rank alone
as brilliance.

###### Signal B: strength discovery

Some moves are already plausible candidates early, but the engine only
discovers **how strong the move itself is** as the search develops. This is
different from rank/regret discovery: a move may already be rank 1 while its
practical winning chance rises dramatically.

For strength discovery:

- the move must finish at final **rank 1**;
- it must be present in at least two snapshots in every search phase;
- it must be Top 3 in at least **50%** of its usable early snapshots;
- median practical winning chance must improve by at least
  **5 percentage points** from early to middle;
- it must improve by at least another **5 percentage points** from middle to
  late;
- total early-to-late improvement must be at least **20 percentage points**;
- the move must remain rank 1 in at least two of the last three late snapshots.

Winning chance rather than raw centipawns is used intentionally. A change from
+5 to +10 in an already overwhelmingly won position therefore does not look
artificially spectacular merely because the centipawn number doubled.

Kramnik-Leko 2004 `...Qd3` is a regression example for this second pattern:
the move is already a serious candidate at low depth, but its practical
strength grows dramatically through the middle and late search phases.

##### Signal C: causal material investment

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
immediate reply to recover material. This recovery reply is evaluated even when
the capture occurred on the final ply of the six-ply detection horizon, so the
reply itself is the first ply just beyond that horizon. This prevents ordinary
exchanges at the horizon boundary from being interpreted as sacrifices.
Additional unrelated loss on that reply is not charged to the original move.

The remaining material deficit relative to the root position is still measured
for diagnostics, but material alone is considered strong enough to justify
`!!` from **3 points** onward.

A typical exchange sacrifice (rook for bishop or knight, net 2 points) may still be objectively strong and may receive `!` or `!!` for other independent reasons, but the material investment by itself does not create a brilliant annotation. The three-point threshold is deliberately chosen so that the Nezhmetdinov `Qxf6` combination, whose net material investment is 3 despite the much larger gross queen sacrifice, can still qualify through the material signal.

Examples the model is intended to distinguish:

```text
Qxf6 ... forced sequence -> net investment is measured, even when the queen's
                             gross value is larger
Bxc6 ...dxc6          -> ordinary equal exchange, no signal
Nc3 ...Nxc3 | bxc3     -> capture at horizon boundary; immediate recovery still
                          counts, no false three-point investment
...Bxf1 Kxf1          -> material gain for Black, no investment
...Rxf7 ...Nxf7       -> net investment 2, recorded but insufficient alone for !!
e4 ... later Q loss   -> no signal for e4 because the e-pawn was not sacrificed
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
- large regret reduction across early/middle/late phases -> `!!`;
- Kramnik-Leko `...Qd3` strength discovery -> `!!`;
- stable best move with only small strength growth -> no `!!`;
- sound queen sacrifice -> material `!!`;
- objectively bad queen sacrifice -> remains `??`;
- unrelated later material loss -> does not make the root move brilliant;
- ordinary equal exchange -> no material `!!`;
- normal development -> no material `!!`;
- Black score normalization;
- practical winning-chance thresholds for `?` and `??`;
- a large raw evaluation drop in an already won position does not automatically become `??`.

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
