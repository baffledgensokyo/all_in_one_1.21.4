@echo off
where py.exe >nul 2>nul
if errorlevel 1 (
    python "%~dp0build_equipment_atlas.py" %*
) else (
    py -3 "%~dp0build_equipment_atlas.py" %*
)
set "tmt_atlas_exit=%errorlevel%"
echo.
pause
exit /b %tmt_atlas_exit%
