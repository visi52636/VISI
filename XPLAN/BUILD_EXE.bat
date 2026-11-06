@echo off
REM ====================================================================
REM  Build ONE standalone XPLAN.exe  (no Python needed to RUN it after)
REM  Run this once on a Windows PC that has Python installed.
REM  Result: a single file  ->  dist\XPLAN.exe
REM
REM  If xplan_data.json is present next to this script, your clients are
REM  embedded inside the .exe and appear automatically on first run.
REM  The running program keeps its live data in  %APPDATA%\XPLAN  so the
REM  .exe itself stays a single standalone file.
REM ====================================================================
cd /d "%~dp0"
setlocal

echo Installing/updating PyInstaller and openpyxl...
py -3 -m pip install --upgrade pyinstaller openpyxl 2>nul || python -m pip install --upgrade pyinstaller openpyxl

set ADDDATA=
if exist xplan_data.json (
    copy /Y xplan_data.json xplan_seed.json >nul
    set ADDDATA=--add-data "xplan_seed.json;."
    echo Your data will be embedded in the .exe as a first-run seed.
) else (
    echo No xplan_data.json found - building an empty program.
)

echo.
echo Building a single-file XPLAN.exe ...
py -3 -m PyInstaller --onefile --windowed --name XPLAN %ADDDATA% xplan.py 2>nul || python -m PyInstaller --onefile --windowed --name XPLAN %ADDDATA% xplan.py

if exist xplan_seed.json del xplan_seed.json >nul

echo.
echo ====================================================================
echo  Done.  Your single program file is:   dist\XPLAN.exe
echo  Copy that one file anywhere and double-click it to run.
echo  (Your clients/payments are saved in  %%APPDATA%%\XPLAN )
echo ====================================================================
pause
