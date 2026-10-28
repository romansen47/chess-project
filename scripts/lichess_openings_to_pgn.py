#!/usr/bin/env python3
"""Convert the pinned lichess-org/chess-openings TSV catalog to importable PGN."""

from __future__ import annotations

import argparse
import csv
import io
from pathlib import Path
from urllib.request import urlopen

FILES = ("a.tsv", "b.tsv", "c.tsv", "d.tsv", "e.tsv")
DEFAULT_REVISION = "e76b8b4ec5c8aeeba41dac6caf4a60b938f652db"
SOURCE_REPOSITORY = "lichess-org/chess-openings"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate chess-project PGN opening catalog from Lichess TSV data."
    )
    parser.add_argument(
        "--revision",
        default=DEFAULT_REVISION,
        help="Lichess chess-openings Git revision to read and record in PGN tags.",
    )
    parser.add_argument(
        "--source-dir",
        type=Path,
        help="Optional local checkout/directory containing a.tsv through e.tsv.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("target/lichess-openings.pgn"),
        help="PGN output path.",
    )
    return parser.parse_args()


def read_source(file_name: str, revision: str, source_dir: Path | None) -> str:
    if source_dir is not None:
        return (source_dir / file_name).read_text(encoding="utf-8")
    url = (
        "https://raw.githubusercontent.com/"
        f"{SOURCE_REPOSITORY}/{revision}/{file_name}"
    )
    with urlopen(url) as response:  # noqa: S310 - fixed HTTPS GitHub host
        return response.read().decode("utf-8")


def escape_tag(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def opening_blocks(revision: str, source_dir: Path | None) -> list[str]:
    blocks: list[str] = []
    move_sequences: set[str] = set()

    for file_name in FILES:
        source = read_source(file_name, revision, source_dir)
        reader = csv.DictReader(io.StringIO(source), delimiter="\t")
        if reader.fieldnames != ["eco", "name", "pgn"]:
            raise ValueError(
                f"Unexpected columns in {file_name}: {reader.fieldnames!r}"
            )

        for row_number, row in enumerate(reader, start=2):
            eco = (row.get("eco") or "").strip()
            name = (row.get("name") or "").strip()
            moves = (row.get("pgn") or "").strip()
            if not eco or not name or not moves:
                raise ValueError(
                    f"Incomplete opening at {file_name}:{row_number}"
                )
            if moves in move_sequences:
                raise ValueError(
                    f"Duplicate exact move sequence at {file_name}:{row_number}: {moves}"
                )
            move_sequences.add(moves)

            blocks.append(
                "\n".join(
                    (
                        f'[Opening "{escape_tag(name)}"]',
                        f'[ECO "{escape_tag(eco)}"]',
                        '[Result "*"]',
                        f'[Source "{SOURCE_REPOSITORY}"]',
                        f'[SourceRevision "{escape_tag(revision)}"]',
                        "",
                        f"{moves} *",
                    )
                )
            )

    return blocks


def main() -> None:
    args = parse_args()
    blocks = opening_blocks(args.revision, args.source_dir)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n\n".join(blocks) + "\n", encoding="utf-8")
    print(
        f"Wrote {len(blocks)} opening lines to {args.output} "
        f"from {SOURCE_REPOSITORY}@{args.revision}"
    )


if __name__ == "__main__":
    main()
