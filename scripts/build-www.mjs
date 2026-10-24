// Builds www/ for the Android app from the single-file game in game/echo-loop.html.
// - wraps the page in a full HTML document
// - swaps Google Fonts for bundled font files (the app must work offline)
// - bundles src/native.js (AdMob, Play Billing, haptics, back button) and loads it first
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const www = join(root, 'www');
rmSync(www, { recursive: true, force: true });
mkdirSync(join(www, 'fonts'), { recursive: true });

const FONTS = [
  ['tektur', 'Tektur', [700, 900]],
  ['chakra-petch', 'Chakra Petch', [500, 600, 700]],
];
let fontCss = '';
for (const [pkg, family, weights] of FONTS) {
  for (const w of weights) {
    const file = `${pkg}-latin-${w}-normal.woff2`;
    copyFileSync(join(root, 'node_modules/@fontsource', pkg, 'files', file), join(www, 'fonts', file));
    fontCss += `@font-face{font-family:"${family}";font-style:normal;font-weight:${w};font-display:swap;src:url(fonts/${file}) format("woff2")}\n`;
  }
}

let page = readFileSync(join(root, 'game/echo-loop.html'), 'utf8');
const fontLinks = /<link rel="preconnect"[^>]*>\s*<link rel="preconnect"[^>]*>\s*<link rel="stylesheet" href="https:\/\/fonts\.googleapis\.com[^>]*>\s*/;
if (!fontLinks.test(page)) throw new Error('Google Fonts links not found in game/echo-loop.html');
page = page.replace(fontLinks, `<style>\n${fontCss}</style>\n`);
const scriptTag = '<script>\n(() => {';
if (!page.includes(scriptTag)) throw new Error('game script not found');
page = page.replace(scriptTag, '<script src="native.js"></script>\n' + scriptTag);

const bodyAt = page.indexOf('<canvas id="game"');
if (bodyAt < 0) throw new Error('canvas not found');
page = page.slice(0, bodyAt) + '</head>\n<body>\n' + page.slice(bodyAt);

const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
<meta name="theme-color" content="#07050f">
${page}
</body>
</html>
`;
writeFileSync(join(www, 'index.html'), html);

await build({
  entryPoints: [join(root, 'src/native.js')],
  bundle: true,
  format: 'iife',
  target: 'es2019',
  minify: true,
  outfile: join(www, 'native.js'),
  logLevel: 'warning',
});
console.log('www/ built');
