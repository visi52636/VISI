@echo off
REM ====================================================================
REM  Build a standalone XPLAN.exe (no Python needed to run it afterwards)
REM  Run this ONCE on a Windows machine that has Python installed.
REM  The finished program appears in the "dist" folder as XPLAN.exe
REM ====================================================================
cd /d "%~dp0"

echo Installing/updating PyInstaller and openpyxl...
py -3 -m pip install --upgrade pyinstaller openpyxl
if %errorlevel% neq 0 (
    python -m pip install --upgrade pyinstaller openpyxl
)

echo.
echo Building XPLAN.exe ...
py -3 -m PyInstaller --onefile --windowed --name XPLAN xplan.py
if %errorlevel% neq 0 (
    python -m PyInstaller --onefile --windowed --name XPLAN xplan.py
)

echo.
echo ====================================================================
echo  Done. Your program is:  dist\XPLAN.exe
echo.
echo  Copy these together into one folder to use it:
echo      dist\XPLAN.exe
echo      xplan_data.json      (your clients and payments)
echo  XPLAN.exe keeps its data file next to itself.
echo ====================================================================
pause
