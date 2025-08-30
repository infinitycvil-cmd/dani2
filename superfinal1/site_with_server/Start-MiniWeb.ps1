<# 
 Start-MiniWeb.ps1
 One-click static site server for Windows using HttpListener.
 Drop this script into the folder with your index.html and run it.
 It will:
  - Elevate to admin if needed
  - Reserve the URL ACL and open the firewall for the chosen port
  - Serve the current folder over HTTP
  - Show URLs you can use (localhost, LAN IPv4/IPv6, and public IPv4 if detectable)
  - Clean up URL ACL and firewall rule on exit
#>

param(
    [int]$Port = 8080,
    [string]$Root = $PSScriptRoot
)

function Ensure-Admin {
    $current = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $current.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        Write-Host "Elevating to Administrator..."
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Port $Port -Root `"$Root`""
        $psi.Verb = "runas"
        [Diagnostics.Process]::Start($psi) | Out-Null
        exit
    }
}

Ensure-Admin

# Reserve URL ACL (ignore errors if it already exists)
$url = "http://+:$Port/"
try { & netsh http add urlacl url=$url user="Everyone" > $null 2>&1 } catch {}

# Open firewall inbound rule (ignore if it exists already)
$ruleName = "MiniWeb_$Port"
try { & netsh advfirewall firewall add rule name="$ruleName" dir=in action=allow protocol=TCP localport=$Port > $null 2>&1 } catch {}

# MIME types
$Mime = @{
  ".html"="text/html"; ".htm"="text/html"; ".css"="text/css"; ".js"="application/javascript";
  ".json"="application/json"; ".png"="image/png"; ".jpg"="image/jpeg"; ".jpeg"="image/jpeg";
  ".gif"="image/gif"; ".svg"="image/svg+xml"; ".ico"="image/x-icon"; ".txt"="text/plain";
  ".pdf"="application/pdf"; ".webp"="image/webp"; ".wasm"="application/wasm"; ".mp4"="video/mp4";
  ".mp3"="audio/mpeg"; ".wav"="audio/wav"; ".woff"="font/woff"; ".woff2"="font/woff2"
}

Add-Type -AssemblyName System.Net.HttpListener

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add($url)
$listener.Start()

# Compute addresses
try {
    $ifaces = Get-NetIPAddress -AddressFamily IPv4,IPv6 -PrefixOrigin Dhcp,Manual |
        Where-Object { $_.IPAddress -notlike "169.254.*" -and $_.IPAddress -ne "::1" -and $_.IPAddress -notlike "fe80*" }
} catch { $ifaces = @() }

$localV4 = ($ifaces | Where-Object {$_.AddressFamily -eq "IPv4"} | Select-Object -ExpandProperty IPAddress -ErrorAction SilentlyContinue) -join ", "
$localV6 = ($ifaces | Where-Object {$_.AddressFamily -eq "IPv6"} | Select-Object -ExpandProperty IPAddress -ErrorAction SilentlyContinue) -join ", "

# Try to fetch public IPv4 via OpenDNS (best effort; may fail)
$publicV4 = $null
try {
    $ns = (nslookup -type=A myip.opendns.com resolver1.opendns.com) 2>$null
    $match = ($ns | Select-String -Pattern 'Address:\s*(\d{1,3}(\.\d{1,3}){3})' -AllMatches)
    if ($match.Matches.Count -gt 0) {
        $publicV4 = $match.Matches[-1].Groups[1].Value
    }
} catch {}

Write-Host "========================================================================="
Write-Host " Serving folder: $Root"
Write-Host " Listening on:   http://localhost:$Port/"
if ($localV4) { Write-Host (" LAN IPv4:       http://{0}:{1}/" -f ($localV4 -split ", ")[0], $Port) }
if ($localV6) { Write-Host (" LAN IPv6:       http://[{0}]:{1}/" -f ($localV6 -split ", ")[0], $Port) }
if ($publicV4) { Write-Host (" Public IPv4:    http://{0}:{1}/  (requires router port forward)" -f $publicV4, $Port) }
Write-Host " Press Ctrl+C to stop."
Write-Host "========================================================================="

function Send-Bytes($ctx,[byte[]]$bytes,[int]$status=200,[string]$contentType="text/plain") {
    $ctx.Response.StatusCode = $status
    $ctx.Response.ContentType = $contentType
    $ctx.Response.ContentLength64 = $bytes.Length
    $ctx.Response.Headers["Cache-Control"] = "public, max-age=60"
    $ctx.Response.OutputStream.Write($bytes,0,$bytes.Length)
    $ctx.Response.OutputStream.Close()
}

function Get-ContentType($path) {
    $ext = [IO.Path]::GetExtension($path).ToLower()
    if ($Mime.ContainsKey($ext)) { return $Mime[$ext] } else { return "application/octet-stream" }
}

# Path traversal protection
$Root = [IO.Path]::GetFullPath($Root)
if (-not $Root.EndsWith([IO.Path]::DirectorySeparatorChar)) { $Root += [IO.Path]::DirectorySeparatorChar }

# Handle Ctrl+C gracefully
$script:stopping = $false
$onExit = {
    try { $listener.Stop() } catch {}
    try { & netsh http delete urlacl url=$url > $null 2>&1 } catch {}
    try { & netsh advfirewall firewall delete rule name="$ruleName" > $null 2>&1 } catch {}
}
$null = Register-EngineEvent PowerShell.Exiting -Action $onExit

while ($listener.IsListening) {
    try {
        $ctx = $listener.GetContext()
        $rel = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
        if ([string]::IsNullOrWhiteSpace($rel)) { $rel = "index.html" }

        $reqPath = Join-Path -Path $Root -ChildPath $rel
        $full = [IO.Path]::GetFullPath($reqPath)

        if ($full -notlike "$Root*") {
            Send-Bytes $ctx ([Text.Encoding]::UTF8.GetBytes("403 Forbidden")) 403 "text/plain"
            continue
        }

        if (Test-Path $full -PathType Container) {
            $default = Join-Path $full "index.html"
            if (Test-Path $default) {
                $full = $default
            } else {
                $items = Get-ChildItem $full | Sort-Object { $_.PSIsContainer } -Descending
                $html = "<!doctype html><meta charset='utf-8'><title>Index of /$rel</title><h1>Index of /$rel</h1><ul>" +
                    (($items | ForEach-Object {
                        $name = $_.Name
                        $href = if ($rel) { "$rel/$name" } else { $name }
                        "<li><a href=""$href"">$name</a></li>"
                    }) -join "`n") + "</ul>"
                Send-Bytes $ctx ([Text.Encoding]::UTF8.GetBytes($html)) 200 "text/html"
                continue
            }
        }

        if (-not (Test-Path $full -PathType Leaf)) {
            Send-Bytes $ctx ([Text.Encoding]::UTF8.GetBytes("404 Not Found")) 404 "text/plain"
            continue
        }

        $bytes = [IO.File]::ReadAllBytes($full)
        $ct = Get-ContentType $full
        Send-Bytes $ctx $bytes 200 $ct
        Write-Host ("{0} {1} -> {2}" -f $ctx.Request.RemoteEndPoint,$ctx.Request.RawUrl,$full)

    } catch {
        if ($listener.IsListening) {
            Write-Warning $_.Exception.Message
        }
    }
}

# Final cleanup in case exit event missed
& netsh http delete urlacl url=$url > $null 2>&1
& netsh advfirewall firewall delete rule name="$ruleName" > $null 2>&1
