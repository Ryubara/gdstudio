#!/usr/bin/env bash
# Make a game from one of the kit's templates: double-click this file (or run it from a terminal).
# The game lands in <workspace>/repos/<name>/ as a local repository; nothing goes to GitHub.
# Windows: new-game.cmd beside this file runs it with Git Bash when .sh files open elsewhere.
# The steps it runs: docs/engines/godot/new-game.md#double-click
set -u

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

finish() {
  echo
  read -r -p "Press Enter to close." _ || true
  exit "$1"
}

# The workspace is the folder above the kit holding the marker every tool looks for (docs/studio/workspace.md).
WORKSPACE="$KIT"
while [ ! -e "$WORKSPACE/.gdstudio-workspace" ]; do
  if [ "$WORKSPACE" = "$(dirname "$WORKSPACE")" ]; then
    echo "No .gdstudio-workspace above $KIT: run this from the kit inside a GDStudio workspace."
    finish 1
  fi
  WORKSPACE="$(dirname "$WORKSPACE")"
done

gds() {
  (cd "$KIT" && uv run --quiet --project "$KIT/python" gds "$@")
}

if ! command -v uv >/dev/null 2>&1; then
  echo "uv was not found on PATH. Run the workspace bootstrap first (docs/studio/workspace.md#bootstrap)."
  finish 1
fi

echo "GDStudio: a new game from a template"
echo "Workspace: $WORKSPACE"
echo

# No mapfile: macOS ships bash 3.2.
LINES=()
while IFS= read -r line; do
  [ -n "$line" ] && LINES+=("$line")
done < <(gds new game --list | tr -d '\r')
if [ "${#LINES[@]}" -eq 0 ]; then
  echo "No templates found."
  finish 1
fi

NAMES=()
for i in "${!LINES[@]}"; do
  read -r name description <<<"${LINES[$i]}"
  NAMES+=("$name")
  printf '  %d) %-18s %s\n' "$((i + 1))" "$name" "$description"
done
echo

while true; do
  read -r -p "Template number [1-${#NAMES[@]}]: " pick || finish 1
  pick="${pick%$'\r'}"
  if [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le "${#NAMES[@]}" ]; then
    TEMPLATE="${NAMES[$((pick - 1))]}"
    break
  fi
  echo "Type a number from the list."
done

while true; do
  read -r -p "Game name (lowercase words joined by hyphens, e.g. my-game): " GAME || finish 1
  GAME="${GAME%$'\r'}"
  if [[ ! "$GAME" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)*$ ]]; then
    echo "Use lowercase letters and digits, words joined by single hyphens."
  elif [ -e "$WORKSPACE/repos/$GAME" ]; then
    echo "repos/$GAME already exists: pick another name or delete that folder first."
  else
    break
  fi
done

echo
echo "Making repos/$GAME from $TEMPLATE..."
if ! gds new game "$GAME" --template "$TEMPLATE" --local; then
  echo
  echo "gds new game failed; the lines above say why."
  finish 1
fi

PROJECT="$WORKSPACE/repos/$GAME/game"
echo
echo "Made: $PROJECT"
echo "It is local only: the GitHub steps listed above are for when the game should be published."
read -r -p "Open it in the pinned Godot editor now? [Y/n] " open || open=n
open="${open%$'\r'}"
if [[ ! "$open" =~ ^[Nn] ]]; then
  GODOT="$(gds tool path godot)"
  if [ -z "$GODOT" ] || [ ! -e "$GODOT" ]; then
    echo "The pinned Godot is not installed (gds tool path godot); open $PROJECT yourself."
    finish 1
  fi
  case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*) cmd //c start "" "$(cygpath -w "$GODOT")" --editor --path "$(cygpath -w "$PROJECT")" ;;
    *) nohup "$GODOT" --editor --path "$PROJECT" >/dev/null 2>&1 & ;;
  esac
  echo "Godot is opening."
fi
finish 0
