@echo off
setlocal EnableExtensions
REM Task Force Null Windows setup launcher (cmd.exe / double-click).
REM Forwards every argument to setup.ps1. Bash-style flags are translated.
REM Local LLM install is opt-in. Setup detects a running local server
REM (ports 8080, 11434, 8000) or an installed model before any download.
REM If none is found it asks before Inkling 2 Mini (6.5 GB AD IQ1_S quant).
REM The default answer is No. Decline continues setup.
REM API keys in .env or a remote inference endpoint are then required.
REM   setup.bat -SkipLlm
REM   setup.bat --skip-llm
REM   setup.bat --non-interactive
REM   setup.bat --install-llm

set "PSARGS="
:parse
if "%~1"=="" goto run
if /I "%~1"=="--help" goto help
if /I "%~1"=="-h" goto help
if /I "%~1"=="/?" goto help
if /I "%~1"=="--dry-run" set "PSARGS=%PSARGS% -DryRun" & shift & goto parse
if /I "%~1"=="-DryRun" set "PSARGS=%PSARGS% -DryRun" & shift & goto parse
if /I "%~1"=="--non-interactive" set "PSARGS=%PSARGS% -NonInteractive" & shift & goto parse
if /I "%~1"=="-NonInteractive" set "PSARGS=%PSARGS% -NonInteractive" & shift & goto parse
if /I "%~1"=="--skip-llm" set "PSARGS=%PSARGS% -SkipLlm" & shift & goto parse
if /I "%~1"=="-SkipLlm" set "PSARGS=%PSARGS% -SkipLlm" & shift & goto parse
if /I "%~1"=="--install-llm" set "PSARGS=%PSARGS% -InstallLlm" & shift & goto parse
if /I "%~1"=="-InstallLlm" set "PSARGS=%PSARGS% -InstallLlm" & shift & goto parse
if /I "%~1"=="--skip-keys" set "PSARGS=%PSARGS% -SkipKeys" & shift & goto parse
if /I "%~1"=="-SkipKeys" set "PSARGS=%PSARGS% -SkipKeys" & shift & goto parse
if /I "%~1"=="--skip-deploy" set "PSARGS=%PSARGS% -SkipDeploy" & shift & goto parse
if /I "%~1"=="-SkipDeploy" set "PSARGS=%PSARGS% -SkipDeploy" & shift & goto parse
if /I "%~1"=="--harness" set "PSARGS=%PSARGS% -Harness %~2" & shift & shift & goto parse
if /I "%~1"=="-Harness" set "PSARGS=%PSARGS% -Harness %~2" & shift & shift & goto parse
if /I "%~1"=="--mission-slug" set "PSARGS=%PSARGS% -MissionSlug %~2" & shift & shift & goto parse
if /I "%~1"=="-MissionSlug" set "PSARGS=%PSARGS% -MissionSlug %~2" & shift & shift & goto parse
if /I "%~1"=="--install-harness" set "PSARGS=%PSARGS% -InstallHarness %~2" & shift & shift & goto parse
if /I "%~1"=="-InstallHarness" set "PSARGS=%PSARGS% -InstallHarness %~2" & shift & shift & goto parse
set "PSARGS=%PSARGS% %~1"
shift
goto parse

:help
echo Task Force Null setup. Local LLM is opt-in (Inkling 2 Mini, 6.5 GB AD IQ1_S).
echo The default is No. Decline continues: use API keys in .env or a remote inference endpoint.
echo Flags: -DryRun -NonInteractive -SkipLlm -InstallLlm -SkipKeys -SkipDeploy
echo        -Harness NAME -MissionSlug SLUG -InstallHarness NAME
echo Bash-style --dry-run --skip-llm --install-llm --non-interactive are accepted.
exit /b 0

:run
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0setup.ps1" %PSARGS%
exit /b %ERRORLEVEL%
