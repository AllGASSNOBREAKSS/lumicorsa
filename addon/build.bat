@echo off
rem Release build with MSVC (x64 Native Tools prompt or run tools\vcvars first).
cmake -S "%~dp0" -B "%~dp0build" -A x64 || exit /b 1
cmake --build "%~dp0build" --config Release || exit /b 1
copy /y "%~dp0build\Release\photolap.addon64" "%~dp0..\bin\photolap.addon64"
