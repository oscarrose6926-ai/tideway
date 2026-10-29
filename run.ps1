# Dev launcher: starts FastAPI (:8000) and Vite (:5173) together.
# Ctrl+C stops both. Windows equivalent of run.sh.

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$py = Join-Path $root '.venv\Scripts\python.exe'
if (-not (Test-Path $py)) {
    Write-Error "No venv at $root\.venv - create one and run: pip install -r requirements.txt"
    exit 1
}

$web = Join-Path $root 'web'
if (-not (Test-Path (Join-Path $web 'node_modules'))) {
    Write-Host "Installing frontend deps..."
    Push-Location $web
    try { & npm install } finally { Pop-Location }
}

# Keep the port in sync with what the FastAPI app tells its global
# media-key listener. Without this, the listener defaults to 47823
# (the packaged-app port) and the media-key POSTs silently 404 in
# dev because uvicorn is actually on 8000. Child processes started by
# Start-Process inherit this environment.
$env:TIDAL_DL_PORT = '8000'

# Start-Process with -NoNewWindow pipes stdout/stderr into this console so
# both servers' logs interleave here, matching run.sh's behavior.
Write-Host "Starting FastAPI on http://127.0.0.1:$env:TIDAL_DL_PORT"
$api = Start-Process -FilePath $py `
    -ArgumentList '-m', 'uvicorn', 'server:app', '--host', '127.0.0.1', '--port', $env:TIDAL_DL_PORT, '--reload' `
    -WorkingDirectory $root -PassThru -NoNewWindow

Write-Host "Starting Vite on http://127.0.0.1:5173"
# npm on Windows is npm.cmd; Start-Process can't invoke .cmd scripts
# directly, so route through cmd /c.
$webProc = Start-Process -FilePath 'cmd.exe' `
    -ArgumentList '/c', 'npm', 'run', 'dev', '--', '--host', '127.0.0.1', '--port', '5173' `
    -WorkingDirectory $web -PassThru -NoNewWindow

try {
    Wait-Process -Id $api.Id, $webProc.Id
}
finally {
    foreach ($p in @($api, $webProc)) {
        if ($p -and -not $p.HasExited) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        }
    }
}
