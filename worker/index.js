// Cloudflare Worker for the web build. Serves the static app, plus a
// `/drive/<file id>?token=...&format=...` proxy: a browser's audio player
// can't send Google Drive's Authorization header, so this adds it and passes
// byte ranges through (Safari won't play audio without them).

const audioTypes = {
  flac: 'audio/flac',
  mp3: 'audio/mpeg',
  m4a: 'audio/mp4',
  aac: 'audio/aac',
  ogg: 'audio/ogg',
  oga: 'audio/ogg',
  opus: 'audio/ogg',
  wav: 'audio/wav',
};

// Response headers worth keeping from Drive; everything else is dropped.
const passThrough = ['content-length', 'content-range', 'etag', 'last-modified'];

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (!url.pathname.startsWith('/drive/')) return env.ASSETS.fetch(request);
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response('Method not allowed', { status: 405, headers: { Allow: 'GET, HEAD' } });
    }

    const id = url.pathname.slice('/drive/'.length);
    const token = url.searchParams.get('token');
    if (!/^[\w-]+$/.test(id) || !token) return new Response('Bad request', { status: 400 });

    const range = request.headers.get('Range');
    const drive = await fetch(`https://www.googleapis.com/drive/v3/files/${id}?alt=media`, {
      method: request.method,
      headers: { Authorization: `Bearer ${token}`, ...(range && { Range: range }) },
    });
    if (!drive.ok) {
      return new Response(drive.body, {
        status: drive.status,
        headers: { 'Content-Type': drive.headers.get('Content-Type') ?? 'text/plain' },
      });
    }

    const headers = new Headers({
      'Accept-Ranges': 'bytes',
      // The URL carries a short-lived token; keep it out of shared caches.
      'Cache-Control': 'private, no-store',
      'Referrer-Policy': 'no-referrer',
    });
    for (const name of passThrough) {
      const value = drive.headers.get(name);
      if (value) headers.set(name, value);
    }
    // Drive reports what the uploader's client guessed, often
    // application/octet-stream, which Safari refuses to play.
    const type = drive.headers.get('Content-Type') ?? '';
    const format = url.searchParams.get('format')?.toLowerCase();
    headers.set('Content-Type', type.startsWith('audio/') ? type : audioTypes[format] ?? type);

    return new Response(drive.body, { status: drive.status, headers });
  },
};
