#!/usr/bin/env bash
set -euo pipefail

max_source_bytes="${MAX_SOURCE_BYTES:-32768}"
status=0

while IFS= read -r -d '' source_file; do
  byte_count=$(wc -c < "$source_file")
  if (( byte_count > max_source_bytes )); then
    printf 'Source file exceeds %d bytes: %s (%d bytes)\n' \
      "$max_source_bytes" "$source_file" "$byte_count" >&2
    status=1
  fi
done < <(
  find chess chess-api chess-database chess-frontend \
    -type f \
    \( -name '*.java' -o -name '*.ts' -o -name '*.tsx' -o -name '*.css' \) \
    -not -path '*/node_modules/*' \
    -not -path '*/target/*' \
    -not -path '*/dist/*' \
    -print0
)

if (( status != 0 )); then
  printf 'Split the file by responsibility before merging.\n' >&2
  exit "$status"
fi

printf 'Source-size check passed (maximum %d bytes per file).\n' "$max_source_bytes"
