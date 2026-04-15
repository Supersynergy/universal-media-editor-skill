#!/usr/bin/env bash
set -euo pipefail

REPO="Supersynergy/universal-media-editor-skill"
RAW="https://raw.githubusercontent.com/${REPO}/main"
INSTALL_DIR="${ME_INSTALL_DIR:-$HOME/.local/share/media-edit}"
SKILL_DIR="${ME_SKILL_DIR:-$HOME/.gg/skills}"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '\033[32m✅\033[0m %s\n' "$*"; }
warn() { printf '\033[33m⚠\033[0m  %s\n' "$*"; }
err()  { printf '\033[31m❌\033[0m %s\n' "$*" >&2; }

bold "🎬 Installing Universal Media Editor…"
echo

[ "$(uname)" = "Darwin" ] || { err "macOS only."; exit 1; }
command -v brew >/dev/null 2>&1 || { warn "Install Homebrew first: https://brew.sh"; exit 1; }
ok "Homebrew detected"

BREW_TOOLS=(ffmpeg whisper-cpp rubberband sox alass dovi_tool hdr10plus_tool mediainfo mpv)
PY_TOOLS=(auto-editor demucs scenedetect ffmpeg-normalize)

bold "📦 Homebrew tools"
brew install "${BREW_TOOLS[@]}" 2>&1 | grep -E '(Pouring|already|installed)' || true

bold "📦 Python tools (via uv)"
if command -v uv >/dev/null 2>&1; then
  for t in "${PY_TOOLS[@]}"; do
    uv tool install "$t" 2>&1 | tail -1 || warn "skip $t"
  done
else
  warn "uv not found — install from https://astral.sh/uv  (then re-run to add $PY_TOOLS)"
fi

bold "📥 Fetching media-edit.sh"
mkdir -p "$INSTALL_DIR"
curl -fsSL "$RAW/media-edit.sh" -o "$INSTALL_DIR/media-edit.sh"
chmod +x "$INSTALL_DIR/media-edit.sh"
ok "$INSTALL_DIR/media-edit.sh"

mkdir -p "$INSTALL_DIR/recipes"
for r in podcast tiktok cinema; do
  curl -fsSL "$RAW/recipes/${r}.recipe" -o "$INSTALL_DIR/recipes/${r}.recipe" 2>/dev/null || true
done
ok "recipes/ installed"

if mkdir -p "$SKILL_DIR" 2>/dev/null; then
  curl -fsSL "$RAW/skill/universal-media-editor.md" -o "$SKILL_DIR/universal-media-editor.md" 2>/dev/null \
    && ok "Skill → $SKILL_DIR/universal-media-editor.md" \
    || warn "Skill not installed (optional)"
fi

SHELL_RC=""
case "${SHELL:-}" in
  */zsh)  SHELL_RC="$HOME/.zshrc" ;;
  */bash) SHELL_RC="$HOME/.bashrc" ;;
esac

LINE="source \"$INSTALL_DIR/media-edit.sh\"  # universal-media-editor-skill"
if [ -n "$SHELL_RC" ]; then
  if [ -f "$SHELL_RC" ] && grep -Fq "$LINE" "$SHELL_RC"; then
    ok "Already wired into $SHELL_RC"
  else
    echo "$LINE" >> "$SHELL_RC"
    ok "Added to $SHELL_RC"
  fi
fi

echo
bold "🎉 Done!"
echo "   Run: source ${SHELL_RC:-~/.zshrc} && me_info"
echo "   Try: media-edit help   |   me_polish my_video.mp4"
