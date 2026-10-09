// Serveur de recette : sert la vitrine et le client web, et relaie /api vers le backend sur la MÊME
// origine, exactement comme le reverse proxy de production (donc aucune configuration CORS).
import { createServer, request as httpRequest } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { dirname, extname, join, normalize, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.png': 'image/png', '.svg': 'image/svg+xml', '.webmanifest': 'application/manifest+json', '.txt': 'text/plain; charset=utf-8' };

export function startServer({ port = 0, backend = 'http://127.0.0.1:3998' } = {}) {
  const target = new URL(backend);
  const server = createServer(async (req, res) => {
    const url = new URL(req.url, 'http://x');
    if (url.pathname.startsWith('/api/')) {
      const headers = { ...req.headers, host: target.host };
      // La recette simule des appareils distincts : le proxy transmet l'adresse annoncée par le test.
      if (req.headers['x-e2e-ip']) headers['x-forwarded-for'] = req.headers['x-e2e-ip'];
      const upstream = httpRequest({ host: target.hostname, port: target.port, path: req.url, method: req.method, headers }, (up) => {
        res.writeHead(up.statusCode, up.headers);
        up.pipe(res);
      });
      upstream.on('error', () => { res.writeHead(502); res.end('bad gateway'); });
      req.pipe(upstream);
      return;
    }
    let path = normalize(decodeURIComponent(url.pathname)).replace(/^(\.\.[/\\])+/, '');
    if (path.endsWith('/')) path += 'index.html';
    let file = join(root, path);
    try {
      if ((await stat(file)).isDirectory()) file = join(file, 'index.html');
      if (!file.startsWith(root) || file.includes(`${root}/test`) || file.includes('node_modules')) throw new Error('interdit');
      const body = await readFile(file);
      res.writeHead(200, { 'Content-Type': TYPES[extname(file)] ?? 'application/octet-stream', 'X-Content-Type-Options': 'nosniff' });
      res.end(body);
    } catch {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('not found');
    }
  });
  return new Promise((ok) => server.listen(port, '127.0.0.1', () => ok({ server, port: server.address().port })));
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { port } = await startServer({ port: Number(process.env.PORT ?? 8081) });
  console.log(`http://127.0.0.1:${port}`);
}
