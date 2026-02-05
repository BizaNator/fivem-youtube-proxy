#!/bin/bash
#
# FiveM YouTube Proxy - Automated Setup Script
# Fixes YouTube embeds in FiveM loading screens using Cloudflare Workers
#
# Usage: ./setup.sh
#

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     FiveM YouTube Loading Screen Fix - Setup Script       ║"
echo "║                  Cloudflare Workers Edition               ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check for Node.js
if ! command -v node &> /dev/null; then
    echo -e "${RED}❌ Node.js is required but not installed.${NC}"
    echo "   Install from: https://nodejs.org/"
    exit 1
fi
echo -e "${GREEN}✓${NC} Node.js found: $(node --version)"

# Check for npx
if ! command -v npx &> /dev/null; then
    echo -e "${RED}❌ npx is required but not installed.${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} npx found"

# Create project directory
PROJECT_DIR="fivem-youtube-proxy"
if [ -d "$PROJECT_DIR" ]; then
    echo -e "${YELLOW}⚠️  Directory '$PROJECT_DIR' already exists.${NC}"
    read -p "   Overwrite? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    rm -rf "$PROJECT_DIR"
fi

mkdir -p "$PROJECT_DIR/src"
cd "$PROJECT_DIR"

echo ""
echo -e "${BLUE}Creating worker script...${NC}"

# Create the worker script
cat > src/index.js << 'WORKER_EOF'
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
WORKER_EOF

echo -e "${GREEN}✓${NC} Worker script created"

# Get user input for configuration
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Configuration - You'll need info from your Cloudflare dashboard${NC}"
echo ""
echo "Find these at: dash.cloudflare.com → Your Domain → Overview (right sidebar)"
echo ""

read -p "Enter your Cloudflare Account ID: " ACCOUNT_ID
read -p "Enter your Zone ID (for your domain): " ZONE_ID
read -p "Enter your domain (e.g., yourdomain.com): " DOMAIN
read -p "Enter subdomain for proxy (default: yt): " SUBDOMAIN
SUBDOMAIN=${SUBDOMAIN:-yt}

# Create wrangler.toml
cat > wrangler.toml << EOF
name = "youtube-proxy"
main = "src/index.js"
compatibility_date = "2024-01-01"
account_id = "$ACCOUNT_ID"

routes = [
  { pattern = "$SUBDOMAIN.$DOMAIN/*", zone_id = "$ZONE_ID" }
]
EOF

echo -e "${GREEN}✓${NC} Configuration saved to wrangler.toml"

# Login and deploy
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Authenticating with Cloudflare...${NC}"
echo ""

npx wrangler login

echo ""
echo -e "${BLUE}Deploying worker...${NC}"
npx wrangler deploy

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Worker deployed successfully!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANT: Add this DNS record in Cloudflare Dashboard:${NC}"
echo ""
echo "   Dashboard → $DOMAIN → DNS → Add Record"
echo ""
echo "   ┌──────────┬──────────┬──────────┬───────────┐"
echo "   │ Type     │ Name     │ Content  │ Proxy     │"
echo "   ├──────────┼──────────┼──────────┼───────────┤"
echo "   │ AAAA     │ $SUBDOMAIN        │ 100::    │ Proxied ✓ │"
echo "   └──────────┴──────────┴──────────┴───────────┘"
echo ""
echo -e "${GREEN}Once DNS is added, your proxy will be live at:${NC}"
echo ""
echo -e "   ${BLUE}https://$SUBDOMAIN.$DOMAIN/?list=YOUR_PLAYLIST_ID&autoplay=1&mute=1${NC}"
echo ""
echo "Update your FiveM loading screen to use this URL!"
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
