# 🧠 FiveM YouTube Loading Screen Fix

**Tired of YouTube videos not playing in your FiveM loading screen?** We were too.

FiveM's NUI browser doesn't send proper HTTP headers that YouTube requires, breaking all video embeds. This free Cloudflare Worker fixes it in minutes.

[![Deploy with Cloudflare](https://img.shields.io/badge/Deploy-Cloudflare%20Workers-F38020?style=for-the-badge&logo=cloudflare&logoColor=white)](https://workers.cloudflare.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)

**🧠 BrainDeadGuild**

*Don't Be BrAIn Dead Alone*

*Games | AI | Community*

[![BrainDeadGuild](https://img.shields.io/badge/BrainDeadGuild-Community-purple.svg)](https://braindeadguild.com/discord) [![BrainDead.TV](https://img.shields.io/badge/BrainDead.TV-Lore-red.svg)](https://braindead.tv/)

## 🎯 About BrainDeadGuild

**BrainDeadGuild** started in 2008 as a gaming community and evolved into a collaboration of gamers, streamers, AI creators, and game developers. We're focused on:

- 🎮 **Game Development** — FiveM, UEFN / Fortnite projects
- 🧠 **AI-Assisted Creation** — tools and workflows
- 📺 **BrainDead.TV** — shared lore, characters, and worlds (including the City of Brains universe)

The tools we release (like this one) are built for our own game and content pipelines, then shared openly when they're useful to others.

---

## The Problem

FiveM's NUI (embedded Chromium browser) doesn't send proper HTTP `Referer` headers when loading YouTube embeds. YouTube requires valid Referer headers per their [Terms of Service](https://developers.google.com/youtube/terms/required-minimum-functionality), so videos fail to load with errors like:

- "Video unavailable"
- "Playback on other websites has been disabled by the video owner"
- Black screen / infinite loading

This affects **all FiveM servers** trying to use YouTube videos or playlists in their loading screens.

## The Solution

Host a tiny HTML proxy page on a real domain that:
1. Receives the video/playlist parameters
2. Creates a YouTube embed iframe with proper headers
3. Lets the video stream directly from YouTube to the player

**The proxy only serves ~2KB of HTML** - actual video bandwidth goes directly from YouTube to players. Your server is never in the video path.

```
Player's FiveM Client          Your Proxy (Cloudflare)         YouTube CDN
        │                              │                            │
        │── GET proxy.yourdomain.com ─▶│                            │
        │◀── 2KB HTML + iframe ────────│                            │
        │                                                           │
        │──────────── Video stream (direct) ───────────────────────▶│
```

---

## Quick Start

### Windows (PowerShell)
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/BizaNator/fivem-youtube-proxy/main/setup.ps1" -OutFile "setup.ps1"
.\setup.ps1
```

### Linux / macOS
```bash
curl -fsSL https://raw.githubusercontent.com/BizaNator/fivem-youtube-proxy/main/setup.sh -o setup.sh
chmod +x setup.sh && ./setup.sh
```

### Or Clone & Run
```bash
git clone https://github.com/BizaNator/fivem-youtube-proxy.git
cd fivem-youtube-proxy
./setup.sh   # or .\setup.ps1 on Windows
```

---

## Manual Setup (Cloudflare Workers - Free)

### Prerequisites
- A domain on Cloudflare (free plan works)
- Node.js installed locally

### Step 1: Create the Worker

```bash
# Create project directory
mkdir youtube-proxy && cd youtube-proxy
mkdir -p src

# Download the worker script
curl -fsSL https://raw.githubusercontent.com/BizaNator/fivem-youtube-proxy/main/src/index.js -o src/index.js
```

### Step 2: Configure Wrangler

Create `wrangler.toml`:
```toml
name = "youtube-proxy"
main = "src/index.js"
compatibility_date = "2024-01-01"

# Get these from your Cloudflare dashboard:
# Account ID: dash.cloudflare.com → any domain → Overview → right sidebar
# Zone ID: dash.cloudflare.com → your domain → Overview → right sidebar
account_id = "YOUR_ACCOUNT_ID"

routes = [
  { pattern = "yt.yourdomain.com/*", zone_id = "YOUR_ZONE_ID" }
]
```

### Step 3: Deploy

```bash
# Login to Cloudflare (opens browser)
npx wrangler login

# Deploy the worker
npx wrangler deploy
```

### Step 4: Add DNS Record

In Cloudflare Dashboard → Your Domain → DNS → Add Record:

| Type | Name | Content | Proxy |
|------|------|---------|-------|
| AAAA | yt | 100:: | ✅ Proxied |

The `100::` is a dummy address - Cloudflare's proxy intercepts requests and routes them to your Worker.

### Step 5: Update Your Loading Screen

Change your loading screen config to use the proxy:

```javascript
// Before (broken)
videoUrl: "https://www.youtube.com/embed/VIDEO_ID?autoplay=1"

// After (working)
videoUrl: "https://yt.yourdomain.com/?v=VIDEO_ID&autoplay=1&mute=1"
```

---

## URL Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `v` | YouTube video ID | - |
| `list` | YouTube playlist ID | - |
| `autoplay` | Auto-start video | `1` |
| `mute` | Muted playback | `1` |
| `controls` | Show player controls | `0` |
| `loop` | Loop video/playlist | `1` |
| `index` | Start at playlist index | `0` |

## Examples

```
# Single video
https://yt.yourdomain.com/?v=dQw4w9WgXcQ&autoplay=1&mute=1

# Playlist
https://yt.yourdomain.com/?list=PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf&autoplay=1&mute=1

# Specific video in playlist
https://yt.yourdomain.com/?v=dQw4w9WgXcQ&list=PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf

# With controls visible
https://yt.yourdomain.com/?v=dQw4w9WgXcQ&controls=1
```

---

## Cost

**$0** - Cloudflare Workers free tier includes:
- 100,000 requests/day
- Unlimited bandwidth (you only serve ~2KB HTML; video comes from YouTube)

Even a server with 1,000 daily unique players would use only 1% of the free quota.

---

## Alternative: Self-Hosted

If you prefer not to use Cloudflare, you can host the `youtube-proxy.html` file on any web server:

1. Download `youtube-proxy.html` from this repo
2. Upload to any HTTPS-enabled host (GitHub Pages, Netlify, your own server)
3. Use that URL in your loading screen config

The key requirement is that it's served from a real HTTP(S) domain, not from `nui://` or local files.

---

## Why This Works

YouTube's embed player checks the `Referer` header to verify the embed is authorized. FiveM's NUI browser (Chromium-based) doesn't send proper Referer headers for security reasons.

By loading a page from a real domain first, that page's Referer is sent to YouTube when the iframe loads. The `referrerpolicy="strict-origin-when-cross-origin"` meta tag ensures the header is sent correctly.

---

## Troubleshooting

**Video still not playing?**
- Ensure your proxy URL uses HTTPS
- Check browser console for errors (F8 in FiveM)
- Verify the video isn't age-restricted or region-locked

**DNS not resolving?**
- Wait 1-2 minutes for propagation
- Ensure the DNS record has orange cloud (Proxied) enabled
- Try `dig yt.yourdomain.com` to verify

**Worker not deploying?**
- Run `npx wrangler whoami` to verify authentication
- Check account_id and zone_id in wrangler.toml

---

## Community & Support

**🧠 Don't Be BrAIn Dead Alone!**

[![Discord](https://img.shields.io/badge/Discord-Join%20Us-5865F2?style=for-the-badge&logo=discord&logoColor=white)](https://BrainDeadGuild.com/discord)
[![Website](https://img.shields.io/badge/Website-BrainDeadGuild.com-FF6B6B?style=for-the-badge)](https://BrainDeadGuild.com)

- **Discord**: [BrainDeadGuild.com/discord](https://BrainDeadGuild.com/discord) - Get help, share creations, suggest features
- **Website**: [BrainDeadGuild.com](https://BrainDeadGuild.com)
- **Lore & Content**: [BrainDead.TV](https://BrainDead.TV)
- **GitHub**: [github.com/BizaNator](https://github.com/BizaNator)

### Other BrainDead Tools

Check out our other free tools for creators:

| Tool | Description |
|------|-------------|
| [BrainDead Background Remover](https://github.com/BizaNator/BrainDeadBackgroundRemover) | Free AI-powered background removal tool |
| [ComfyUI-BrainDead](https://github.com/BizaNator/ComfyUI-BrainDead) | Custom nodes for ComfyUI - character consistency, prompt tools, and more |
| [BrainDeadBlender](https://github.com/BizaNator/BrainDeadBlender) | Blender add-ons for 3D artists and game developers |

---

## License

MIT - Free to use, modify, and share.

---

*A [Biloxi Studios Inc.](https://BrainDeadGuild.com) Production*
