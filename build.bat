@echo off
setlocal

rem Builds the PL_MPEG library (vendored, untouched, in src/) into a static
rem archive that the Odin binding in pl_mpeg.odin links against.
rem
rem Usage:
rem   build.bat                :: produces libplmpeg.a
rem   build.bat path\libx.a    :: custom output path
rem
rem Defaults to a MinGW gcc/ar toolchain. Set CC/AR to override; setting CC
rem to cl (MSVC) produces a .lib via lib instead.

set "TARGET=libplmpeg.a"
if not "%~1"=="" set "TARGET=%~1"

if not defined CC set "CC=gcc"
if not defined AR set "AR=ar"

echo %CC% | findstr /i "clang" >nul
if not errorlevel 1 goto :mingw

echo %CC% | findstr /i "cl" >nul
if not errorlevel 1 goto :msvc

:mingw
echo Compiling with %CC% ...
%CC% -O2 -Isrc -c pl_mpeg_odin.c -o pl_mpeg_odin.o
if errorlevel 1 exit /b 1
%AR% rcs "%TARGET%" pl_mpeg_odin.o
if errorlevel 1 exit /b 1
goto :finish

:msvc
echo Compiling with %CC% ...
%CC% /O2 /Isrc /c pl_mpeg_odin.c /Fo:pl_mpeg_odin.obj
if errorlevel 1 exit /b 1
lib /out:"%TARGET%" pl_mpeg_odin.obj
if errorlevel 1 exit /b 1

:finish
del /q pl_mpeg_odin.o pl_mpeg_odin.obj >nul 2>&1
echo built %TARGET%
endlocal