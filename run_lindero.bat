@echo off
setlocal
cd /d "%~dp0"

:: Busca Godot 4.6 en rutas comunes o en PATH. No asume una PC en particular.
set GODOT_EXE=

if defined GODOT_PATH if exist "%GODOT_PATH%" set "GODOT_EXE=%GODOT_PATH%"

if not defined GODOT_EXE where godot >nul 2>&1 && for /f "delims=" %%i in ('where godot') do (
  set "GODOT_EXE=%%i"
  goto :found
)

for %%P in (
  "%LOCALAPPDATA%\Godot\Godot_v4.6*_win64.exe"
  "%USERPROFILE%\Downloads\Godot_v4.6*_win64.exe"
  "%USERPROFILE%\source\Godot_v4.6*_win64.exe\Godot_v4.6*_win64.exe"
  "C:\Program Files\Godot\Godot*.exe"
) do (
  if not defined GODOT_EXE for %%F in (%%~P) do (
    if exist "%%~F" (
      set "GODOT_EXE=%%~F"
      goto :found
    )
  )
)

:found
if not defined GODOT_EXE (
  echo No encuentro Godot 4.6.
  echo 1^) Descargalo de https://godotengine.org/download
  echo 2^) O define GODOT_PATH con la ruta al .exe
  echo 3^) O abri Godot y importa project.godot de esta carpeta.
  pause
  exit /b 1
)

echo Usando: %GODOT_EXE%
if "%1"=="editor" (
  start "" "%GODOT_EXE%" -e --path "%cd%"
  goto :eof
)
if "%1"=="menu" (
  start "" "%GODOT_EXE%" --path "%cd%" "res://scenes/menu.tscn"
  goto :eof
)

start "" "%GODOT_EXE%" --path "%cd%" "res://scenes/menu.tscn"
