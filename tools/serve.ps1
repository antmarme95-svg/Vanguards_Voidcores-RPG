# BORISAWA zero-dependency static server.
# ES modules cannot load over file://, so this serves the project on localhost.
param([int]$Port = 8420, [switch]$NoBrowser)

$root = Split-Path -Parent $PSScriptRoot
$prefix = "http://localhost:$Port/"

$mime = @{
  ".html" = "text/html; charset=utf-8"
  ".js"   = "text/javascript; charset=utf-8"
  ".mjs"  = "text/javascript; charset=utf-8"
  ".css"  = "text/css; charset=utf-8"
  ".json" = "application/json; charset=utf-8"
  ".png"  = "image/png"
  ".jpg"  = "image/jpeg"
  ".svg"  = "image/svg+xml"
  ".ico"  = "image/x-icon"
  ".md"   = "text/plain; charset=utf-8"
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)
try {
  $listener.Start()
} catch {
  Write-Host "Could not bind $prefix ($_). Is the game already running?" -ForegroundColor Red
  exit 1
}

Write-Host ""
Write-Host "  BORISAWA is live at $prefix" -ForegroundColor Cyan
Write-Host "  (Press Ctrl+C in this window to stop the server)" -ForegroundColor DarkGray
Write-Host ""

if (-not $NoBrowser) { Start-Process $prefix }

while ($listener.IsListening) {
  try { $ctx = $listener.GetContext() } catch { break }
  $req = $ctx.Request
  $res = $ctx.Response
  try {
    $path = [Uri]::UnescapeDataString($req.Url.AbsolutePath)
    if ($path -eq "/") { $path = "/index.html" }
    $file = Join-Path $root ($path -replace "/", "\")
    $full = [IO.Path]::GetFullPath($file)
    if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path $full -PathType Leaf)) {
      $res.StatusCode = 404
      $bytes = [Text.Encoding]::UTF8.GetBytes("404 - lost in The Wilds")
    } else {
      $ext = [IO.Path]::GetExtension($full).ToLower()
      $type = $mime[$ext]; if (-not $type) { $type = "application/octet-stream" }
      $res.ContentType = $type
      $res.AddHeader("Cache-Control", "no-cache")
      $bytes = [IO.File]::ReadAllBytes($full)
    }
    $res.ContentLength64 = $bytes.Length
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
  } catch {
    # client aborted or read failure; keep serving
  } finally {
    try { $res.OutputStream.Close() } catch {}
  }
}
$listener.Stop()
