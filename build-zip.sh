#!/usr/bin/env zsh
# Builds a zip archive for installing the todo plugin via `claude plugin install --file`
set -euo pipefail

PLUGIN_NAME="todo-plugin"
VERSION=$(grep '"version"' .claude-plugin/plugin.json | head -1 | sed 's/.*: *"\(.*\)".*/\1/')
OUT="${PLUGIN_NAME}-${VERSION}.zip"

STAGING="$TMPDIR/${PLUGIN_NAME}-staging"
rm -rf "$STAGING" "$OUT"
mkdir -p "$STAGING/$PLUGIN_NAME"

cp -r .claude-plugin "$STAGING/$PLUGIN_NAME/"
cp -r commands "$STAGING/$PLUGIN_NAME/"
cp CLAUDE.md README.md "$STAGING/$PLUGIN_NAME/"
cp skills/todo/SKILL.md "$STAGING/$PLUGIN_NAME/"

(cd "$STAGING" && zip -r - "$PLUGIN_NAME" -x '*.DS_Store') > "$OUT"
rm -rf "$STAGING"

echo "Built $OUT"
