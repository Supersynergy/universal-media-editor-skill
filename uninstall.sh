#!/usr/bin/env bash
set -euo pipefail
INSTALL_DIR="${ME_INSTALL_DIR:-$HOME/.local/share/media-edit}"
SKILL="$HOME/.gg/skills/universal-media-editor.md"
STATS="$HOME/.media-edit"

echo "🗑  Uninstalling media-edit…"
rm -rf "$INSTALL_DIR" && echo "  ✅ removed $INSTALL_DIR"
[ -f "$SKILL" ] && rm -f "$SKILL" && echo "  ✅ removed skill"

for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  [ -f "$rc" ] || continue
  if grep -q 'universal-media-editor-skill' "$rc"; then
    cp "$rc" "$rc.me-bak"
    grep -v 'universal-media-editor-skill' "$rc.me-bak" > "$rc"
    echo "  ✅ cleaned $rc"
  fi
done

read -r -p "Delete stats at $STATS? [y/N] " a
[ "$a" = "y" ] || [ "$a" = "Y" ] && rm -rf "$STATS" && echo "  ✅ stats removed"
echo "👋 done. Brew tools left alone."
