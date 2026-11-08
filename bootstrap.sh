#!/bin/sh
# Sets up a GDStudio workspace on Linux or macOS: installs uv if it is missing, then runs `gds workspace init`
# (docs/studio/workspace.md#bootstrap). Every argument is passed on to init.
#
# From a clone of the kit at <workspace>/repos/gdstudio:  ./bootstrap.sh
# On its own, building a new workspace (clones the kit):  sh bootstrap.sh --workspace ~/GDStudio
set -eu

# The uv release installed when uv is missing; Astral's installer puts it in ~/.local/bin and adds it to PATH in your
# shell profiles (set UV_NO_MODIFY_PATH=1 to stop that).
uv_version=0.12.17
kit_url=https://github.com/Ryubara/gdstudio.git

if ! command -v git >/dev/null 2>&1; then
    echo "bootstrap: Git is required (and Git LFS: https://git-lfs.com)" >&2
    exit 2
fi
if ! command -v uv >/dev/null 2>&1; then
    echo "bootstrap: installing uv $uv_version (https://docs.astral.sh/uv/)"
    curl -LsSf "https://astral.sh/uv/$uv_version/install.sh" | sh
    PATH="$HOME/.local/bin:$PATH"
    export PATH
fi

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ ! -f "$here/python/pyproject.toml" ]; then
    # On its own: make the workspace, clone the kit into it, and continue from that clone.
    workspace=$(pwd)
    previous=""
    for argument in "$@"; do
        case "$argument" in
            --workspace=*) workspace=${argument#--workspace=} ;;
        esac
        if [ "$previous" = "--workspace" ]; then workspace=$argument; fi
        previous=$argument
    done
    here="$workspace/repos/gdstudio"
    if [ ! -d "$here" ]; then
        mkdir -p "$workspace/repos"
        git clone "$kit_url" "$here"
    fi
fi

exec uv run --project "$here/python" gds workspace init "$@"
