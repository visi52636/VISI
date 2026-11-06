@echo off
REM ====================================================================
REM  XPLAN - Client & Payment Manager  (Windows launcher)
REM  Double-click this file to start the program.
REM ====================================================================
cd /d "%~dp0"

REM Try the Windows Python launcher first, then plain "python".
where py >nul 2>&1
if %errorlevel%==0 (
    py -3 xplan.py
    goto :eof
)

where python >nul 2>&1
if %errorlevel%==0 (
    python xplan.py
    goto :eof
)

echo.
echo  Python was not found on this computer.
echo.
echo  Please install Python 3 (free) from:
echo      https://www.python.org/downloads/
echo.
echo  IMPORTANT: during install tick the box
echo      "Add python.exe to PATH"
echo  and leave "tcl/tk and IDLE" enabled (it is on by default).
echo.
echo  Then double-click run_XPLAN.bat again.
echo.
pause
