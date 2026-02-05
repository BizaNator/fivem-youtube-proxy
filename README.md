# FiveM YouTube Loading Screen Fix

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

## Quick Setup (Cloudflare Workers - Free)

### Prerequisites
- A domain on Cloudflare (free plan works)
- Node.js installed locally

### Step 1: Create the Worker

```bash
# Create project directory
mkdir youtube-proxy && cd youtube-proxy
mkdir -p src

# Create the worker script
cat > src/index.js << 'EOF'
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
EOF

echo "✅ Worker script created"
```

### Step 2: Configure Wrangler

```bash
# Create wrangler.toml (edit YOUR_ACCOUNT_ID and YOUR_ZONE_ID)
cat > wrangler.toml << 'EOF'
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
EOF

echo "⚠️  Edit wrangler.toml with your account_id and zone_id"
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

## Cost

**$0** - Cloudflare Workers free tier includes:
- 100,000 requests/day
- Unlimited bandwidth (you only serve ~2KB HTML; video comes from YouTube)

Even a server with 1,000 daily unique players would use only 1% of the free quota.

## Alternative: Self-Hosted

If you prefer not to use Cloudflare, you can host the HTML file on any web server:

1. Save the HTML content to `youtube-proxy.html`
2. Upload to any HTTPS-enabled host (GitHub Pages, Netlify, your own server)
3. Use that URL in your loading screen config

The key requirement is that it's served from a real HTTP(S) domain, not from `nui://` or local files.

## Why This Works

YouTube's embed player checks the `Referer` header to verify the embed is authorized. FiveM's NUI browser (Chromium-based) doesn't send proper Referer headers for security reasons.

By loading a page from a real domain first, that page's Referer is sent to YouTube when the iframe loads. The `referrerpolicy="strict-origin-when-cross-origin"` meta tag ensures the header is sent correctly.

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

## License

MIT - Free to use, modify, and share.

---

*This solution was developed to solve a common FiveM community issue. If it helped your server, consider sharing it with others!*
