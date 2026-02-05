#Requires -Version 5.1
<#
.SYNOPSIS
    FiveM YouTube Loading Screen Fix - Setup Script (Windows)

.DESCRIPTION
    Fixes YouTube embeds in FiveM loading screens using Cloudflare Workers.
    This script creates and deploys a Cloudflare Worker that proxies YouTube
    embed requests with proper Referer headers.

.NOTES
    Requires: Node.js (https://nodejs.org/)
    Cost: Free (Cloudflare Workers free tier)
#>

$ErrorActionPreference = "Stop"

# Colors for output
function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    if ($args) {
        Write-Output $args
    }
    $host.UI.RawUI.ForegroundColor = $fc
}

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     FiveM YouTube Loading Screen Fix - Setup Script       ║" -ForegroundColor Cyan
Write-Host "║                  Cloudflare Workers Edition               ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check for Node.js
try {
    $nodeVersion = node --version
    Write-Host "✓ Node.js found: $nodeVersion" -ForegroundColor Green
} catch {
    Write-Host "❌ Node.js is required but not installed." -ForegroundColor Red
    Write-Host "   Download from: https://nodejs.org/" -ForegroundColor Yellow
    exit 1
}

# Check for npx
try {
    $null = Get-Command npx -ErrorAction Stop
    Write-Host "✓ npx found" -ForegroundColor Green
} catch {
    Write-Host "❌ npx is required but not installed." -ForegroundColor Red
    exit 1
}

# Create project directory
$ProjectDir = "fivem-youtube-proxy"
if (Test-Path $ProjectDir) {
    Write-Host "⚠️  Directory '$ProjectDir' already exists." -ForegroundColor Yellow
    $confirm = Read-Host "   Overwrite? (y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Host "Aborted."
        exit 0
    }
    Remove-Item -Recurse -Force $ProjectDir
}

New-Item -ItemType Directory -Path "$ProjectDir\src" -Force | Out-Null
Set-Location $ProjectDir

Write-Host ""
Write-Host "Creating worker script..." -ForegroundColor Cyan

# Create the worker script
$WorkerScript = @'
const HTML_CONTENT = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="referrer" content="strict-origin-when-cross-origin">
    <title>Video Player</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        html, body { width: 100%; height: 100%; background: #000; overflow: hidden; }
        iframe { width: 100%; height: 100%; border: none; }
    </style>
</head>
<body>
    <iframe
        id="player"
        referrerpolicy="strict-origin-when-cross-origin"
        allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
        allowfullscreen>
    </iframe>
    <script>
        (function() {
            const params = new URLSearchParams(window.location.search);
            const videoId = params.get('v');
            const playlistId = params.get('list');

            if (!videoId && !playlistId) {
                document.body.innerHTML = '<p style="color:#fff;text-align:center;padding:20px;">No video specified</p>';
                return;
            }

            const embedParams = new URLSearchParams({
                autoplay: params.get('autoplay') || '1',
                mute: params.get('mute') || '1',
                controls: params.get('controls') || '0',
                loop: params.get('loop') || '1',
                rel: '0',
                modestbranding: '1',
                playsinline: '1',
                enablejsapi: '1',
                origin: window.location.origin
            });

            let embedUrl;
            if (playlistId) {
                embedParams.set('list', playlistId);
                embedParams.set('listType', 'playlist');
                if (params.get('index')) embedParams.set('index', params.get('index'));
                embedUrl = videoId
                    ? \`https://www.youtube-nocookie.com/embed/\${videoId}?\${embedParams.toString()}\`
                    : \`https://www.youtube-nocookie.com/embed/videoseries?\${embedParams.toString()}\`;
            } else {
                embedParams.set('playlist', videoId);
                embedUrl = \`https://www.youtube-nocookie.com/embed/\${videoId}?\${embedParams.toString()}\`;
            }

            document.getElementById('player').src = embedUrl;
        })();
    </script>
</body>
</html>`;

export default {
  async fetch(request, env, ctx) {
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type',
        },
      });
    }

    return new Response(HTML_CONTENT, {
      headers: {
        'Content-Type': 'text/html;charset=UTF-8',
        'Access-Control-Allow-Origin': '*',
        'Cache-Control': 'public, max-age=3600',
        'X-Frame-Options': 'ALLOWALL',
      },
    });
  },
};
'@

$WorkerScript | Out-File -FilePath "src\index.js" -Encoding UTF8
Write-Host "✓ Worker script created" -ForegroundColor Green

# Get user input
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Configuration - You'll need info from your Cloudflare dashboard" -ForegroundColor Yellow
Write-Host ""
Write-Host "Find these at: dash.cloudflare.com → Your Domain → Overview (right sidebar)"
Write-Host ""

$AccountId = Read-Host "Enter your Cloudflare Account ID"
$ZoneId = Read-Host "Enter your Zone ID (for your domain)"
$Domain = Read-Host "Enter your domain (e.g., yourdomain.com)"
$Subdomain = Read-Host "Enter subdomain for proxy (default: yt)"
if ([string]::IsNullOrWhiteSpace($Subdomain)) { $Subdomain = "yt" }

# Create wrangler.toml
$WranglerConfig = @"
name = "youtube-proxy"
main = "src/index.js"
compatibility_date = "2024-01-01"
account_id = "$AccountId"

routes = [
  { pattern = "$Subdomain.$Domain/*", zone_id = "$ZoneId" }
]
"@

$WranglerConfig | Out-File -FilePath "wrangler.toml" -Encoding UTF8
Write-Host "✓ Configuration saved to wrangler.toml" -ForegroundColor Green

# Login and deploy
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Authenticating with Cloudflare..." -ForegroundColor Yellow
Write-Host ""

npx wrangler login

Write-Host ""
Write-Host "Deploying worker..." -ForegroundColor Cyan
npx wrangler deploy

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "✓ Worker deployed successfully!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "⚠️  IMPORTANT: Add this DNS record in Cloudflare Dashboard:" -ForegroundColor Yellow
Write-Host ""
Write-Host "   Dashboard → $Domain → DNS → Add Record"
Write-Host ""
Write-Host "   ┌──────────┬──────────┬──────────┬───────────┐"
Write-Host "   │ Type     │ Name     │ Content  │ Proxy     │"
Write-Host "   ├──────────┼──────────┼──────────┼───────────┤"
Write-Host "   │ AAAA     │ $Subdomain        │ 100::    │ Proxied ✓ │"
Write-Host "   └──────────┴──────────┴──────────┴───────────┘"
Write-Host ""
Write-Host "Once DNS is added, your proxy will be live at:" -ForegroundColor Green
Write-Host ""
Write-Host "   https://$Subdomain.$Domain/?list=YOUR_PLAYLIST_ID&autoplay=1&mute=1" -ForegroundColor Cyan
Write-Host ""
Write-Host "Update your FiveM loading screen to use this URL!"
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green

# Return to original directory
Set-Location ..
