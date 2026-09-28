# Imported comments and clock times

Implementation for [issue #12](https://github.com/romansen47/chess-project/issues/12).

## Data ownership

- `chess` parses and writes PGN comments, evaluations, variations and the standard
  clock (`[%clk h:mm:ss]`) and elapsed-move (`[%emt h:mm:ss]`) annotations.
  Supported fractional seconds are retained to millisecond precision.
  Missing times are null; zero is a valid value. Unsupported time strings stay
  in the comment text. Annotations use one-based plies; ply zero is the
  introductory comment. `MoveList` retains its existing responsibility.
- `chess-database` preserves the original annotated PGN and keeps the compact
  main-line moves and position index unchanged. Schema 5 adds an import staging
  table. Existing databases migrate on opening; older application versions do
  not support schema 5.
- `chess-api` transports the optional `clockMillis` and `elapsedMoveMillis`
  fields through the existing annotations DTO and snapshot/export paths.
- `chess-frontend` derives historical clock displays from the selected main-line
  ply and reuses the clock panel in read-only mode. Mobile analysis shows the
  selected move's comment below the move list in the Moves tab.

## Reimport policy

Game identity still uses players, date, round, result, starting position and
main-line moves. Neither annotations nor times participate in duplicate
recognition or position hashing. Duplicate imports do not increment statistics.

For an identical game, missing annotation fields are filled. Existing comments,
clock values, evaluations, NAGs and non-empty variation lists win on conflict.
Imported variants are not combined with an existing variation list. Repeating
an import is idempotent. The existing import counters still classify duplicate
games as skipped even when their annotations are enriched.

Updates to existing games are staged until the complete import succeeds.
Cancellation/failure removes staged annotations, including those from committed
batches. At publication the merge uses the current stored PGN, preserving edits
made while the import was reading. Ordinary annotation saves remain explicit
replacements of the complete annotation state, including time fields.

## Display rules

After a white move, show its clock and the clock after Black's preceding move;
after a black move, show its clock and the clock after White's preceding move.
Unknown values display `--:--`. A missing value is not replaced by an older one.
Clock tags are not extrapolated from elapsed time or time-control assumptions.
Clock values for an explored variation are unknown. Historical clocks do not run
and their panels do not toggle computer play. The display uses whole seconds;
PGN/API data retain the original milliseconds.

The mobile comment area follows the same selection and annotations as the
existing desktop editor. Long text wraps and scrolls below the move list.

## Validation

GitHub CI runs the Maven reactor, Java regression tests, frontend type checking,
lint, translation audit, Vitest, the Stockfish smoke test and production build.
New regression cases cover time/comment round trips, malformed tags, introductory
comments, enrichment without changing position counts, cancellation after a
committed batch, edits during import, snapshots and historical clock selection.

Suggested manual checks after CI:

1. Import a library containing both comments and `clk` / `emt` annotations.
2. Load a game and jump forward/backward; compare both clocks with the source PGN.
3. On a narrow screen, select the Moves tab and tap several moves. Read their
   comments below the list, including a long multiline comment.
4. Edit a comment on desktop, save, reload and export PGN. Check that times remain.
5. Import an unannotated copy first, then an annotated copy. Verify one game and
   unchanged opening statistics; import a conflicting copy and verify existing
   comments and clock values remain.
6. Check an ordinary game without times and normal live computer-play controls.

Structured extraction currently covers the main line. Variations remain PGN
text; library-wide text search and time statistics are separate work.
