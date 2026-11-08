<#
.SYNOPSIS
    Sets up a GDStudio workspace on Windows: installs uv if it is missing, then runs `gds workspace init`
    (docs/studio/workspace.md#bootstrap). Every argument is passed on to init.

.EXAMPLE
    # From a clone of the kit at <workspace>\repos\gdstudio:
    powershell -ExecutionPolicy Bypass -File bootstrap.ps1
    # On its own, building a new workspace in C:\GDStudio (clones the kit there first):
    powershell -ExecutionPolicy Bypass -File bootstrap.ps1 --workspace C:\GDStudio
#>

$ErrorActionPreference = "Stop"

# The uv release installed when uv is missing; Astral's installer puts it in %USERPROFILE%\.local\bin and adds that
# folder to your user PATH (set UV_NO_MODIFY_PATH=1 to stop that).
$UvVersion = "0.12.17"
$KitUrl = "https://github.com/Ryubara/gdstudio.git"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    [Console]::Error.WriteLine("bootstrap: Git is required (https://git-scm.com/download/win); it includes Git LFS")
    exit 2
}
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Host "bootstrap: installing uv $UvVersion (https://docs.astral.sh/uv/)"
    powershell -ExecutionPolicy ByPass -NoProfile -Command "irm https://astral.sh/uv/$UvVersion/install.ps1 | iex"
    $env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"
}

$Here = $PSScriptRoot
if (-not (Test-Path (Join-Path $Here "python\pyproject.toml"))) {
    # On its own: make the workspace, clone the kit into it, and continue from that clone.
    $Workspace = (Get-Location).Path
    for ($i = 0; $i -lt $args.Count; $i++) {
        if ($args[$i] -eq "--workspace" -and $i + 1 -lt $args.Count) { $Workspace = $args[$i + 1] }
        elseif ($args[$i] -like "--workspace=*") { $Workspace = $args[$i].Substring(12) }
    }
    $Here = Join-Path $Workspace "repos\gdstudio"
    if (-not (Test-Path $Here)) {
        New-Item -ItemType Directory -Force (Split-Path $Here) | Out-Null
        git clone $KitUrl $Here
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
}

& uv run --project (Join-Path $Here "python") gds workspace init @args
exit $LASTEXITCODE
