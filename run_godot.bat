@echo off
setlocal
rem Open the DOTS project in the Godot 4.7 editor (ASCII-only for CP949 cmd).

set "GODOT_DIR=%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe"

rem Prefer the short copy, fall back to the full version name.
set "GODOT=%GODOT_DIR%\godot.exe"
if not exist "%GODOT%" set "GODOT=%GODOT_DIR%\Godot_v4.7-stable_win64.exe"

if not exist "%GODOT%" (
    echo.
    echo [ERROR] Godot executable not found.
    echo Looked in: %GODOT_DIR%
    echo.
    echo Install Godot first with:
    echo     winget install GodotEngine.GodotEngine
    echo.
    pause
    exit /b 1
)

echo Opening Godot editor for project:
echo     %~dp0
start "" "%GODOT%" --path "%~dp0"
endlocal
