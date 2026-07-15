#!/usr/bin/env bash
# Regenerate the C4 diagrams from docs/workspace.dsl.
#
# NOTE: the official `structurizr/cli` Docker image has been SUNSET — its
# entrypoint was replaced with a deprecation banner that exits 0 without doing
# anything. So we fetch the prebuilt CLI zip from GitHub releases and run it
# under a stock Temurin JRE container, then render the PlantUML with the
# plantuml/plantuml image. Hand-authored sequence diagrams (sequence-*.puml)
# are rendered directly.
set -euo pipefail
cd "$(dirname "$0")"

CLI_DIR="$(mktemp -d)"
echo "▶ Fetching Structurizr CLI…"
curl -sL -o "$CLI_DIR/cli.zip" \
  https://github.com/structurizr/cli/releases/latest/download/structurizr-cli.zip
unzip -oq "$CLI_DIR/cli.zip" -d "$CLI_DIR"

echo "▶ Exporting workspace.dsl → PlantUML…"
docker run --rm -v "$PWD":/work -v "$CLI_DIR":/cli -w /work eclipse-temurin:21-jre \
  bash /cli/structurizr.sh export -workspace workspace.dsl -format plantuml/c4plantuml -output .

echo "▶ Rendering all .puml → PNG + SVG…"
for fmt in png svg; do
  docker run --rm -v "$PWD":/work -w /work plantuml/plantuml -t"$fmt" "*.puml"
done

rm -rf "$CLI_DIR"
echo "✓ Diagrams regenerated in $(pwd)"
