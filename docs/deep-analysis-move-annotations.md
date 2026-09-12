# DeepAnalysis move annotations

CAT's move annotations are deterministic chess-domain logic built on finite engine analysis. They are used by completed DeepAnalysis runs and by analysis-mode live reassessment of selected historical moves.

The classifier itself never starts an engine. It receives:

- the position before the played move;
- the played move;
- the engine's final MultiPV candidates;
- intermediate depth snapshots from the same search when available;
- the evaluation of the resulting position.

The frontend only renders the resulting annotation and diagnostic explanation.

## Design goal

CAT does **not** try to imitate a particular chess website's labels and does not attempt to infer an abstract concept such as human genius.

The current model deliberately separates:

1. objective move quality;
2. extraordinary, explainable properties of an objectively sound move;
3. critical best-move detection.

The central design rule is:

> A move receives `!!` only when CAT can name a concrete extraordinary property of an objectively sound move.

This means `!!` should be read as **extraordinary / noteworthy**, not as a universal claim that the move is "brilliant."

A higher frequency of `!!` is acceptable when every annotation remains explainable. Explainability is preferred over complicated rarity heuristics.

## Symbols

| Symbol | Domain kind | Meaning |
| --- | --- | --- |
| `??` | `BLUNDER` | At least 25 percentage points of practical winning chance are lost relative to the best candidate. |
| `?` | `MISTAKE` | At least 10 percentage points of practical winning chance are lost. |
| `!!` | `EXTRAORDINARY` | Objectively sound move with qualifying material-sacrifice and/or deep-discovery evidence. |
| `!` | `ONLY_MOVE` | Critical, non-trivial final best move. |

A move receives at most one visible symbol.

## Classification order

```text
MoveAnnotationClassifier
    |
    +-- objective loss >= 25 ----------------------> ??
    |
    +-- objective loss >= 10 ----------------------> ?
    |
    +-- ExtraordinaryMoveDetector -----------------> !!
    |       |
    |       +-- MaterialSacrificeDetector
    |       |
    |       +-- DeepDiscoveryDetector
    |
    +-- final best + critical + non-trivial ------> !
    |
    +-- otherwise ---------------------------------> no annotation
```

Negative quality has priority. A sacrifice, unusual engine discovery, or tactical idea can never turn a move that currently qualifies as `?` or `??` into `!!`.

`!!` is evaluated before `!`. If the final best move is both critical and extraordinary, `!!` is shown.

## Architecture

The relevant production classes are in:

```text
chess/src/main/java/demo/chess/analysis/annotation/
```

Current responsibilities:

- `MoveAnnotationClassifier` — orchestration and final symbol precedence.
- `ObjectiveMoveQualityEvaluator` — acceptable / mistake / blunder decision.
- `ExtraordinaryMoveDetector` — overall `!!` eligibility and evidence combination.
- `DeepDiscoveryDetector` — detects genuine strengthening of the played move during deeper search.
- `MaterialSacrificeDetector` — combines active and passive sacrifice evidence.
- `MaterialInvestmentDetector` — tracks sacrifice of the moved piece itself.
- `MaterialOfferDetector` — detects new material offers and deliberately declined saves of another piece.
- `OnlyMoveDetector` — suppresses trivial/obvious `!` annotations.
- `SearchTimeline` — shared engine-relative depth-window handling.
- `EvaluationScoring` — mover-centric score normalization, win-percentage conversion, candidate sorting, and root-move matching.
- `MoveAnnotationPolicy` — all annotation tuning constants.

The API maps the core domain result to a DTO. The frontend does not reimplement the classifier.

## Score normalization

Engine evaluations are stored from White's point of view.

Candidate ranking is normalized to the player who made the move:

- White mover: higher White evaluation is better.
- Black mover: lower White evaluation is better.

CAT sorts candidate lines itself and does not assume the engine emitted MultiPV lines in final quality order.

### Practical winning chance

Raw engine evaluation is converted to practical winning chance by `EvaluationScoring`.

For mover-centric score `s` in pawns:

```text
centipawns = s * 100

winPercent =
    50
    + 50 * (
        2 / (1 + exp(-0.00368208 * centipawns))
        - 1
      )
```

This nonlinear mapping is used for the annotation thresholds.

The important effect is that a large centipawn change in a position that is already overwhelmingly won does not automatically count as an equally large practical error.

## Layer 1: objective quality

The classifier compares the practical winning chance of the best final candidate with the played move:

```text
winChanceLoss =
    winPercent(best move)
    - winPercent(played move)
```

Current thresholds from `MoveAnnotationPolicy`:

```text
MISTAKE_WIN_PERCENT_LOSS = 10.0
BLUNDER_WIN_PERCENT_LOSS = 25.0
```

Therefore:

- loss below 10 -> objectively acceptable for positive annotation purposes;
- loss from 10 up to 25 -> `?`;
- loss at or above 25 -> `??`.

If the played move is missing from final MultiPV, the classifier falls back to the evaluation of the resulting position. This necessarily compares values originating from two separate searches and remains an approximation.

## Layer 2A: extraordinary move eligibility

An extraordinary move must first pass the general quality gate in `ExtraordinaryMoveDetector`.

Current requirements:

```text
EXTRAORDINARY_MAX_FINAL_RANK = 3
EXTRAORDINARY_MAX_FINAL_REGRET_WIN_PERCENT = 10.0
```

The final analysis must contain at least three usable candidates.

The played move must:

- be present in the final Top 3;
- be no more than 10 percentage points of winning chance behind the final best candidate.

After this common gate, CAT checks two independent evidence families:

1. material sacrifice;
2. deep discovery.

If both qualify, the reason is `DEEP_DISCOVERY_AND_MATERIAL_SACRIFICE`.

### Checks are not special-cased

Whether the move gives check is currently diagnostic information only. There is no rule such as "checking moves cannot be extraordinary."

This is intentional. The classifier should not accumulate motif-specific exceptions when the general evidence already explains the annotation.

## Layer 2B: material sacrifice

A material-sacrifice `!!` needs:

```text
EXTRAORDINARY_MATERIAL_INVESTMENT = 3.0
EXTRAORDINARY_MATERIAL_HORIZON_PLIES = 6
EXTRAORDINARY_MATERIAL_MIN_BEST_WIN_PERCENT = 15.0
```

In addition to the common extraordinary gate:

- net investment must be at least 3 material points;
- the final best line must still give the mover at least 15% practical winning chance.

The 15% floor prevents routine liquidation or desperate material loss in an already practically hopeless position from being promoted to `!!` merely because material disappears.

Material values are:

| Piece | Value |
| --- | ---: |
| Pawn | 1 |
| Knight | 3 |
| Bishop | 3 |
| Rook | 5 |
| Queen | 9 |
| King | 0 |

CAT recognizes three sacrifice shapes.

### 1. Active investment

`MaterialInvestmentDetector` handles sacrifice of the piece that actually made the root move.

Requirements:

- replay the candidate engine PV;
- identify the exact moved piece;
- that same piece must be captured within the six-ply horizon;
- measure the mover's material balance before the root move;
- after capture, allow one immediate reply by the sacrificing side;
- credit material recovered by that immediate reply;
- calculate the remaining net deficit.

The immediate recovery is considered even if the capture occurs on the last ply of the nominal six-ply horizon and the recovery therefore lies one ply beyond it.

This avoids false sacrifices from ordinary exchange sequences.

Promotions are excluded because the pawn object is replaced by the promoted piece and therefore does not fit the identity-tracking model. Kings are excluded.

### 2. New material offer

`MaterialOfferDetector` handles a different piece that becomes capturable because of the root move.

The detector:

1. records material balance before the root move;
2. applies the root move;
3. generates legal opponent captures;
4. ignores capture of the root-moved piece because active investment owns that case;
5. checks whether another mover piece can now be legally captured;
6. credits an immediate legal recapture;
7. calculates net material investment relative to the pre-root balance;
8. verifies that the offered piece was **not** already legally capturable before the move.

If the piece was newly exposed and the net investment reaches the threshold, the evidence type is:

```text
NEW_MATERIAL_OFFER
```

### 3. Declined material save

A piece may already be threatened before the root move. CAT only treats leaving it en prise as an intentional sacrifice when the threatened piece itself had at least one legal move to safety.

Then the evidence type is:

```text
DECLINED_MATERIAL_SAVE
```

If the piece was already unavoidably hanging, playing an unrelated move does **not** earn sacrifice credit.

This distinction is essential for the Byrne-Fischer reference case `17...Be6!!`: Black deliberately declines to save the queen, and the net material offer after immediate recovery is six points.

### Why net material is measured before the root move

Passive sacrifice accounting uses the material balance **before** the candidate root move.

This prevents a root move that first wins material from being credited with a sacrifice for giving part of that material back immediately afterwards.

Kramnik-Leko `29.bxc3` is the reference example: `bxc3` itself wins a knight before White's other knight may be lost. The net investment is therefore zero, not three.

## Layer 2C: deep discovery

Deep discovery deliberately has one simple semantic question:

> Does the played move itself become substantially stronger as the same engine search deepens?

The current policy is:

```text
EXTRAORDINARY_DISCOVERY_EARLY_START_RATIO = 0.25
EXTRAORDINARY_DISCOVERY_EARLY_END_RATIO = 0.40
EXTRAORDINARY_DISCOVERY_MIN_EARLY_SNAPSHOTS = 2
EXTRAORDINARY_DISCOVERY_MIN_EARLY_REGRET_WIN_PERCENT = 1.0
EXTRAORDINARY_DISCOVERY_MIN_STRENGTH_GAIN_WIN_PERCENT = 20.0
```

Requirements:

1. the played move must finish at final rank 1;
2. inspect usable snapshots in the 25-40% relative-depth window;
3. each usable snapshot must contain at least three candidate lines;
4. the played move must be present in at least two of those snapshots;
5. calculate the median early regret;
6. calculate the median early practical strength of the played move;
7. early median regret must be at least 1 percentage point;
8. final strength minus early median strength must be at least 20 percentage points.

Regret is:

```text
regret =
    winPercent(best move in snapshot)
    - winPercent(played move in snapshot)
```

Strength is simply the played move's own practical winning chance.

The use of **relative depth** is intentional. Stockfish and Lc0 use very different search depth scales; an absolute depth such as 20 is therefore not treated as engine-independent evidence.

### Why the previous phase model was removed

Earlier versions used multiple coupled signals:

- early/middle/late phases;
- rank movement;
- regret improvement across phases;
- stability requirements;
- Top-3 ratios;
- phase-step thresholds.

That model could produce false positives when all alternatives deteriorated faster than the played move. Kramnik-Leko `26.Kf2` was the decisive example: it could rise relatively while its own absolute practical strength was actually falling.

The current rule prevents this because the played move's **own strength must increase by at least 20 percentage points**.

### Reference case: Kramnik-Leko `25...Qd3!!`

The current diagnostic PGN showed approximately:

```text
earlyDepth     = 6
earlyRank      = 2
earlyRegret    = 5.26 percentage points
earlyStrength  = 61.22%
finalRank      = 1
finalStrength  = 87.48%
```

The reason is therefore directly explainable: deeper search substantially increased the strength of `...Qd3` itself.

## Layer 3: critical non-trivial best move

`OnlyMoveDetector` implements `!`.

Final criticality requires:

```text
ONLY_MOVE_FINAL_WIN_PERCENT_GAP = 15.0
```

The played move must be final rank 1 and lead final rank 2 by at least 15 percentage points of practical winning chance.

CAT then checks whether the move was already trivial early:

```text
ONLY_MOVE_TRIVIAL_EARLY_START_RATIO = 0.30
ONLY_MOVE_TRIVIAL_EARLY_END_RATIO = 0.50
ONLY_MOVE_TRIVIAL_WIN_PERCENT_GAP = 10.0
ONLY_MOVE_TRIVIAL_SNAPSHOT_RATIO = 0.70
ONLY_MOVE_TRIVIAL_MIN_SNAPSHOTS = 2
```

An early snapshot is "obvious" when:

- the played move is already rank 1;
- it leads rank 2 by at least 10 percentage points.

If at least 70% of usable snapshots in the 30-50% window are obvious, `!` is suppressed.

At least two usable early snapshots are required before CAT can call the move trivial. If there is insufficient history, triviality is not established.

## SearchTimeline

`SearchTimeline` centralizes relative-depth handling for both `!` and deep-discovery `!!`.

It:

- determines final depth from final lines and depth history;
- filters unusable snapshots;
- sorts snapshots by depth;
- converts relative ranges into actual depth windows.

This keeps engine-relative search semantics in one place and avoids separate depth logic in every detector.

## Finite analysis and live reassessment

### Completed DeepAnalysis

A complete analysis replays the game and stores per-position engine analysis. Move annotations are calculated by the core classifier from that finite data.

### Live evaluation of a historical move

When a user selects a move during completed analysis, CAT can reassess that historical move.

The continuation engine still evaluates the position after the selected move. In parallel, a second evaluation process analyzes the position before the move and supplies current MultiPV/history data to the same `MoveAnnotationClassifier`.

There is no second frontend classification algorithm.

As live search deepens, an annotation may therefore:

- appear;
- disappear;
- change.

The latest accepted result remains in the current analysis session.

### Temporary analysis variations

Temporary variations use the same live classifier for the latest variation move, but their annotation is transient and is not written into the stored game-analysis profile.

## Diagnostic PGN and debug mode

The diagnostic analysis-PGN export is intentionally a debug feature.

Start CAT with:

```bash
java -DdebugMode -jar chess-api/target/chess-app.jar
```

After a completed analysis, the UI shows **Export analysis PGN**.

Without debug mode, that button is not rendered.

The current export format is:

```text
AnalysisFormat = ChessAnalysisTool-Diagnostic-v2
```

The export contains data useful for understanding classifications, including final candidate evaluations, ranks, extraordinary reason, sacrifice evidence, and deep-discovery diagnostics where available.

It is a diagnostic interchange format, not a stable public PGN extension contract.

## Regression testing

The annotation logic has two complementary test layers.

### General classifier tests

```text
chess/src/test/java/demo/chess/analysis/annotation/
    MoveAnnotationClassifierTest.java
```

These use small deterministic `EngineLine` and `DeepAnalysisResult` fixtures to test general semantic rules without a real engine process.

### Golden real-game regression tests

```text
chess/src/test/java/demo/chess/analysis/annotation/
    MoveAnnotationGoldenRegressionTest.java
```

The golden suite is derived from the real Stockfish 19 / depth-15 diagnostic PGNs used to validate the current classifier.

Protected reference cases include:

| Game | Move | Expected result |
| --- | --- | --- |
| Kramnik-Leko | `23.Qf2` | `??` |
| Kramnik-Leko | `24.Qxe2` | no annotation |
| Kramnik-Leko | `24...Bxe2` | no annotation |
| Kramnik-Leko | `25...Qd3` | `!!` / deep discovery |
| Kramnik-Leko | `26.Kf2` | no annotation |
| Kramnik-Leko | `29.bxc3` | no annotation |
| Nezhmetdinov-Chernikov | `12.Qxf6` | `!!` / active material sacrifice |
| Nezhmetdinov-Chernikov | `17...d6` | `?` |
| Nezhmetdinov-Chernikov | `21...Be2` | `??` |
| Nezhmetdinov-Chernikov | `23.Rh3` | `??` |
| Nezhmetdinov-Chernikov | `24...Bxf1` | `?` |
| Nezhmetdinov-Chernikov | `25.Kxf1` | `?` |
| Nezhmetdinov-Chernikov | `25...Rc8` | `?` |
| Nezhmetdinov-Chernikov | `26.Bd4` | `?` |
| Nezhmetdinov-Chernikov | `29.Rh8+` | `!` |
| Byrne-Fischer | `11.Bg5` | `?` |
| Byrne-Fischer | `11...Na4` | `!` |
| Byrne-Fischer | `17...Be6` | `!!` / declined material save |
| Byrne-Fischer | `18.Bxb6` | `?` |

These tests intentionally make classifier changes visible during `mvn clean install`.

### Golden-test policy

The source test contains an explicit warning and the project follows the same rule:

> **Do not change a golden expectation merely to make a failing build green.**

When a golden test fails after an annotation change:

1. inspect the exact algorithm change;
2. inspect the chess position;
3. compare the original diagnostic engine values;
4. decide whether the new classification is genuinely better;
5. only then update the golden expectation if the behavior change is intentional.

A failing golden test should be treated as a review event, not as test maintenance noise.

### Diagnostic-v2 fixture limitation

Diagnostic-v2 does not serialize every raw intermediate engine snapshot.

For `25...Qd3`, the golden test therefore reconstructs the minimum early history from exported values such as `earlyDepth`, `earlyRank`, `earlyRegret`, and `earlyStrength` while keeping the exported final MultiPV evaluations unchanged.

For unannotated moves, raw early history may not exist in the diagnostic PGN. The fixture uses only the minimum information required to preserve the exported semantic result and documents such reconstruction in the test source.

The tests deliberately avoid inventing hidden engine values merely to reproduce a diagnostic number that cannot be derived from the serialized input.

## Known limitations

### First move

The initial replay point is still not backed by a normal preceding-position engine search in the same way as later moves. Move 1 therefore has limited annotation support.

### MultiPV availability

Extraordinary classification currently requires at least three usable final candidates.

Deep discovery also needs at least three lines in each usable early snapshot.

Time-based searches can finish with fewer complete lines than requested, which can suppress positive annotations.

### Mate handling

Mate evaluations use the existing large numeric score representation. Annotation policy is not yet explicitly mate-distance-aware.

### Engine-specific depth

Relative search depth is only compared inside one search. CAT does not assume that Stockfish depth 20 and Lc0 depth 20 represent equivalent computational effort.

### Material horizon

The active material detector follows the moved piece for six PV plies. A delayed sacrifice accepted beyond that horizon can be missed.

### Material semantics are intentionally narrow

CAT does not attempt to infer all tactical or positional sacrifice concepts from board geometry.

The material signal intentionally answers concrete questions about net material exposure. Positional compensation, king safety, initiative, piece-square value, and long-term strategic compensation remain represented by the engine evaluation rather than by a separate hand-written heuristic.

### Standard-start replay

Material replay reconstructs the game from the standard initial position and its move history. Arbitrary FEN roots and future Chess960 support require corresponding replay support.

## Tuning policy

All numeric annotation thresholds belong in:

```text
chess/src/main/java/demo/chess/analysis/annotation/MoveAnnotationPolicy.java
```

Do not scatter tuning constants through detector implementations.

When behavior is reconsidered:

1. start from real diagnostic examples;
2. add or update deterministic regression coverage;
3. prefer a simple semantic rule over motif-specific exceptions;
4. check the complete golden set;
5. do not optimize for one isolated move at the expense of model clarity.

The current model is intentionally small:

```text
objective quality
    |
    +-- material sacrifice?
    |
    +-- played move itself becomes much stronger with depth?
    |
    +-- critical non-trivial best move?
```

That simplicity is a design constraint, not an accident.
