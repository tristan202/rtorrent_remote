@echo off
rem Kompilerer rTorrent Remote og bygger Inno Setup-installeren i dist\
setlocal
cd /d "%~dp0"

set "PBC=%ProgramFiles%\PureBasic\Compilers\pbcompiler.exe"
set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"

if not exist build mkdir build

"%PBC%" rtorrent_remote.pb /THREAD /XP /DPIAWARE /ICON rtorrent_remote.ico /EXE build\rtorrent_remote.exe
if errorlevel 1 (
  echo Kompilering fejlede.
  exit /b 1
)

"%ISCC%" /Q installer.iss
if errorlevel 1 (
  echo Inno Setup fejlede.
  exit /b 1
)

echo Installer bygget i dist\
