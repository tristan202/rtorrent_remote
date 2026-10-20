@echo off
rem Kompilerer Torrentry og bygger installer + portable zip i dist\
setlocal
cd /d "%~dp0"

set "VERSION=1.0"
set "PBC=%ProgramFiles%\PureBasic\Compilers\pbcompiler.exe"
set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
set "PORT=build\portable\Torrentry"

if not exist build mkdir build
if not exist dist mkdir dist

"%PBC%" torrentry.pb /THREAD /XP /DPIAWARE /ICON torrentry.ico /EXE build\torrentry.exe
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
copy /y build\torrentry.exe "%PORT%\" >nul
copy /y *.lng "%PORT%\" >nul
> "%PORT%\portable.txt" (
  echo Torrentry %VERSION% - portable
  echo.
  echo Mens denne fil ligger ved siden af torrentry.exe, gemmes indstillinger
  echo og servere i servers.ini i denne mappe i stedet for i %%APPDATA%%\Torrentry.
  echo Slet filen for at bruge %%APPDATA%% igen.
)
if exist "dist\Torrentry-%VERSION%-portable.zip" del "dist\Torrentry-%VERSION%-portable.zip"
tar -a -c -f "dist\Torrentry-%VERSION%-portable.zip" -C build\portable Torrentry
if errorlevel 1 (
  echo Portable zip fejlede.
  exit /b 1
)

echo Installer og portable zip bygget i dist\
