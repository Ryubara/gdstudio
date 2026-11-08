@echo off
rem Double-click: makes a game from a template with new-game.sh, run by Git for Windows' bash.
rem Git's bash, never the bash.exe in System32 (that one is WSL).
setlocal
set "GITBASH=%ProgramFiles%\Git\bin\bash.exe"
if not exist "%GITBASH%" set "GITBASH=%LocalAppData%\Programs\Git\bin\bash.exe"
if not exist "%GITBASH%" (
  echo Git for Windows was not found. Install it, or run new-game.sh from Git Bash.
  pause
  exit /b 1
)
rem bash reads the script's own path to find the kit: give it forward slashes.
set "SCRIPT=%~dp0new-game.sh"
set "SCRIPT=%SCRIPT:\=/%"
"%GITBASH%" --login "%SCRIPT%"
