# Lichess opening catalog

The bundled opening catalog is generated from
`lichess-org/chess-openings`, an aggregated opening-name data set released
under CC0 / public domain dedication.

The application JAR carries both the converted catalog and
`META-INF/THIRD-PARTY-NOTICES.txt`, which records the source repository,
pinned revision and CC0 license URL.

Pinned source revision:

`e76b8b4ec5c8aeeba41dac6caf4a60b938f652db`

At this revision the five ECO TSV files (`a.tsv` through `e.tsv`) contain
3,865 distinct exact move sequences. The chess-project representation keeps
every sequence separately; it does not normalize transpositions.

## Runtime behavior

The backend installs missing entries from the bundled PGN during every start.
The operation is idempotent and uses classpath data only. It never contacts
GitHub or Lichess, so an unavailable network or source repository cannot block
an installed CAT version from starting.

The REST and frontend paths for uploading external opening PGNs or manually
triggering the Lichess import are intentionally absent. Updating the catalog is
a release-maintenance operation, not an application-runtime operation.

## Regenerating for a release

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
