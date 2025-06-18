@echo off
REM dev/hooks/install-hooks.bat
REM Windows script to install Git hooks

echo Installing Git hooks...

REM Check if we're in a git repository
if not exist ".git" (
    echo Error: Not in a Git repository. Run this from the root of your repo.
    pause
    exit /b 1
)

REM Create hooks directory if it doesn't exist
if not exist ".git\hooks" mkdir ".git\hooks"

REM Copy and install pre-commit hook
if exist "dev\hooks\pre-commit" (
    copy "dev\hooks\pre-commit" ".git\hooks\pre-commit" >nul
    echo ✓ pre-commit hook installed
) else (
    echo ✗ dev\hooks\pre-commit not found
)

echo Git hooks installation complete!
echo.
echo To test the pre-commit hook:
echo   git add .
echo   git commit -m "test version update"
pause
