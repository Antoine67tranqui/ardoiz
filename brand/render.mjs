// Génère les PNG de la marque à partir des SVG : node brand/render.mjs
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const repo = join(root, '..');
const mark = readFileSync(join(root, 'logo-mark.svg'), 'utf8');
const foreground = readFileSync(join(root, 'logo-foreground.svg'), 'utf8');

const jobs = [
  // [svg, taille, destination, fond]
  [mark, 1024, 'brand/logo-1024.png', null],
  [mark, 512, 'ardoiz-web/assets/logo-512.png', null],
  [mark, 192, 'ardoiz-web/assets/logo-192.png', null],
  [mark, 180, 'ardoiz-web/assets/apple-touch-icon.png', null],
  [mark, 48, 'ardoiz-web/assets/favicon-48.png', null],
  [mark, 32, 'ardoiz-web/assets/favicon-32.png', null],
  // Android : icône carrée classique (mipmap) et premier plan adaptatif (108 dp).
  ...[['mdpi', 48], ['hdpi', 72], ['xhdpi', 96], ['xxhdpi', 144], ['xxxhdpi', 192]].map(([d, s]) => [mark, s, `ardoiz-app/android/app/src/main/res/mipmap-${d}/ic_launcher.png`, null]),
  ...[['mdpi', 108], ['hdpi', 162], ['xhdpi', 216], ['xxhdpi', 324], ['xxxhdpi', 432]].map(([d, s]) => [foreground, s, `ardoiz-app/android/app/src/main/res/drawable-${d}/ic_launcher_foreground.png`, 'transparent']),
];

const browser = await chromium.launch();
const page = await browser.newPage();
for (const [svg, size, dest, bg] of jobs) {
  await page.setViewportSize({ width: size, height: size });
  await page.setContent(`<html><body style="margin:0;background:${bg ?? 'transparent'}">${svg.replace('<svg ', `<svg width="${size}" height="${size}" `)}</body></html>`);
  const png = await page.screenshot({ omitBackground: true, clip: { x: 0, y: 0, width: size, height: size } });
  const out = join(repo, dest);
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, png);
}
await browser.close();
console.log(`${jobs.length} images générées`);
