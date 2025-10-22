#!/usr/bin/env bash
# Usage: ./find_ingredient.sh -i "<ingredient>" -d /path/to/folder
# Input: products.csv (TSV) must exist inside the folder.
# Output: product_name<TAB>code for matches, then a final count line.

set -euo pipefail # safer bash: fail on errors/unset vars/pipelines

# allow up to 1 gb per field
export CSVKIT_FIELD_SIZE_LIMIT=$((1024*1024*1024))

INGREDIENT=""
DATA_DIR=""
CSV=""

usage() {
  echo "usage: $0 -i \"<ingredient>\" -d /path/to/folder"
  echo "  -i: ingredient to search (case-insensitive)"
  echo "  -d: folder containing products.csv (tab-separated)"
  echo "  -h: show help"
}

# parse flags (getopts)
while getopts ":i:d:h" opt; do
  case "$opt" in
    i) INGREDIENT="$OPTARG";;
    d) DATA_DIR="$OPTARG";;
    h) usage; exit 0;;
    \?) echo "invalid option: -$OPTARG" >&2; usage; exit 1;;
    :) echo "option -$OPTARG requires an argument." >&2; usage; exit 1;;
  esac
done

# validate inputs
if [[ -z "${INGREDIENT:-}" ]]; then
  echo "error: -i <ingredient> is required." >&2
  usage
  exit 1
fi

if [[ -z "${DATA_DIR:-}" ]]; then
  echo "error: -d /path/to/folder is required." >&2
  usage
  exit 1
fi

CSV="$DATA_DIR/products.csv"
if [[ ! -s "$CSV" ]]; then
  echo "error: $CSV not found or empty." >&2
  exit 1
fi

# check csvkit tools
for cmd in csvcut csvgrep csvformat; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "error: $cmd not found. please install csvkit and ensure it's in your path." >&2
    exit 1
  fi
done

# create temporary files for intermediate processing
tmp_csv=$(mktemp)
tmp_matches=$(mktemp)

# ensure cleanup happens on script exit
trap 'rm -f "$tmp_csv" "$tmp_matches"' exit

# normalize windows crs (if any) to avoid parsing issues
tr -d '\r' < "$CSV" > "$tmp_csv"

# pipeline:
# 1. select only the columns we need to minimize data processing.
# 2. filter rows for the ingredient (case-insensitive regex).
# 3. select the final output columns.
# 4. format the output as tab-separated.
# 5. remove the header row.
# 6. print matches to the screen and save them to a temp file for counting.
csvcut -t -c ingredients_text,product_name,code "$tmp_csv" | \
  csvgrep -t -c ingredients_text -r "(?i)${INGREDIENT}" | \
  csvcut -c product_name,code | \
  csvformat -T | \
  tail -n +2 | \
  tee "$tmp_matches"

# count the lines in the temp file of matches.
count=$(wc -l < "$tmp_matches" | tr -d ' ')

# print the final summary line.
echo ""
echo "found ${count} product(s) containing: \"${INGREDIENT}\""

rm -f "$tmp_csv" "$tmp_matches"
