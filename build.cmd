@echo off
rem Kompilerer rTorrent Remote og bygger installer + portable zip i dist\
setlocal
cd /d "%~dp0"

set "VERSION=1.0"
set "PBC=%ProgramFiles%\PureBasic\Compilers\pbcompiler.exe"
set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
set "PORT=build\portable\rTorrentRemote"

if not exist build mkdir build
if not exist dist mkdir dist

"%PBC%" rtorrent_remote.pb /THREAD /XP /DPIAWARE /ICON rtorrent_remote.ico /EXE build\rtorrent_remote.exe
if errorlevel 1 (
  echo Kompilering fejlede.
  exit /b 1
)

"%ISCC%" /Q /DAppVersion=%VERSION% installer.iss
if errorlevel 1 (
  echo Inno Setup fejlede.
  exit /b 1
)

rem Portable: exe + portable.txt (faar programmet til at gemme indstillinger i sin egen mappe)
if exist build\portable rmdir /s /q build\portable
mkdir "%PORT%"
copy /y build\rtorrent_remote.exe "%PORT%\" >nul
> "%PORT%\portable.txt" (
  echo rTorrent Remote %VERSION% - portable
  echo.
  echo Mens denne fil ligger ved siden af rtorrent_remote.exe, gemmes indstillinger
  echo og servere i servers.ini i denne mappe i stedet for i %%APPDATA%%\rTorrentRemote.
  echo Slet filen for at bruge %%APPDATA%% igen.
)
if exist "dist\rTorrentRemote-%VERSION%-portable.zip" del "dist\rTorrentRemote-%VERSION%-portable.zip"
tar -a -c -f "dist\rTorrentRemote-%VERSION%-portable.zip" -C build\portable rTorrentRemote
if errorlevel 1 (
  echo Portable zip fejlede.
  exit /b 1
)

echo Installer og portable zip bygget i dist\
