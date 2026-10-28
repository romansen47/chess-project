# Lichess opening catalog

The bundled opening catalog is generated from
`lichess-org/chess-openings`, an aggregated opening-name data set released
under CC0 / public domain dedication.

Pinned source revision:

`e76b8b4ec5c8aeeba41dac6caf4a60b938f652db`

At this revision the five ECO TSV files (`a.tsv` through `e.tsv`) contain
3,865 distinct exact move sequences. The chess-project representation keeps
every sequence separately; it does not normalize transpositions.

## Regenerating

From the umbrella repository:

```bash
python3 scripts/lichess_openings_to_pgn.py \
  --output chess-api/src/main/resources/openings/lichess-openings.pgn
```

The script uses only the Python standard library. For an offline/local source
checkout:

```bash
python3 scripts/lichess_openings_to_pgn.py \
  --source-dir /path/to/chess-openings \
  --revision <source-commit> \
  --output chess-api/src/main/resources/openings/lichess-openings.pgn
```

When updating the pinned revision, also update
`BundledOpeningCatalogService.LICHESS_SOURCE_REVISION` and its expected
catalog entry count. The API integration test imports the complete bundled PGN
and verifies that a repeated import is idempotent.
