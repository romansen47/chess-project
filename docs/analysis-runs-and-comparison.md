# Analysis runs and comparison

CAT uses these user-facing terms consistently:

| Term | Meaning |
| --- | --- |
| Game analysis | Finite analysis of every position in a complete game. |
| Position analysis | Ongoing analysis of the currently selected position. |
| Live evaluation | Ongoing evaluation displayed while a game is being played. |
| Evaluation history | The per-ply evaluation curve of one game. |
| Analysis run | One completed game analysis with an immutable settings snapshot. |
| Analysis comparison | A comparison of two completed runs of the same game. |

Legacy internal names such as `DeepAnalysisEngine` remain protocol and API
compatibility names. They do not define the wording presented to users.

## Persistence boundary

Completed runs are stored in the existing SQLite database. A run contains:

- a stable SHA-256 key derived from the starting position and canonical UCI moves;
- engine name and profile id;
- requested depth or time per position;
- MultiPV and a snapshot of the configured UCI options;
- actual depth, evaluation, mate distance, and engine-ranked principal variations for every analyzed position.

Canonical UCI variants are persisted. Rendered notation, board snapshots, and
arrows are presentation data and are deliberately not database state.

Runs are immutable. Completing a new run makes it active but does not overwrite
older runs. The active run can be changed explicitly.

## Comparison semantics

Runs are aligned by ply and may only be compared when they belong to the same
game key. The engine's MultiPV order is authoritative; numeric values are never
re-sorted to infer a different best move.

For every common position CAT reports:

- whether the best root move differs;
- whether the root move is equal but the continuation differs;
- the common PV prefix length;
- the rank of each engine's best move in the other stored MultiPV, when present;
- raw evaluation, actual depth, mate distance, and normalized-score gap.

“Not in stored MultiPV” is intentionally weaker than “rejected by the engine”.

## Normalized score

For visual comparison CAT maps a pawn evaluation `e` to a common score:

```text
score(e) = 100 / (1 + exp(-0.00368208 * 100 * e))
```

This is a deterministic display normalization. It is **not** presented as a
calibrated win probability. Raw engine evaluations and engine ranking remain
visible and authoritative. Native WDL values may be stored separately in a
future schema version when an engine supplies them reliably.
