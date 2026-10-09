// Captures the hero and a long scroll of each benchmark landing page, for the mood board.
// Needs Google Chrome, and playwright-core beside the script, so run a copy in a scratch folder:
//   mkdir -p /tmp/capture && cp site/moodboard/capture.mjs /tmp/capture && cd /tmp/capture && npm i playwright-core
//   node capture.mjs <repo>/site/moodboard/refs [name ...]
// then make the board's thumbnails:
//   for f in site/moodboard/refs/*-hero.jpg; do sips -Z 900 "$f" --out site/moodboard/refs/thumbs/; done
// The captures are other people's pages, so refs/ stays out of git.
import { chromium } from 'playwright-core';

const out = process.argv[2];
const sites = [
  ['things', 'https://culturedcode.com/things/'],
  ['raycast', 'https://www.raycast.com/'],
  ['cleanshot', 'https://cleanshot.com/'],
  ['ia-writer', 'https://ia.net/writer'],
  ['bear', 'https://bear.app/'],
  ['nova', 'https://nova.app/'],
  ['ghostty', 'https://ghostty.org/'],
  ['tot', 'https://tot.rocks/'],
  ['marked2', 'https://marked2app.com/'],
  ['klack', 'https://tryklack.com/'],
  ['screen-studio', 'https://screen.studio/'],
  ['mela', 'https://mela.recipes/'],
  ['typora', 'https://typora.io/'],
  ['ivory', 'https://tapbots.com/ivory/mac/'],
  ['mimestream', 'https://mimestream.com/'],
  ['kaleidoscope', 'https://kaleidoscope.app/'],
  ['obsidian', 'https://obsidian.md/'],
  ['reeder', 'https://reeder.app/'],
  ['craft', 'https://www.craft.do/'],
  ['zed', 'https://zed.dev/'],
];
const only = process.argv.slice(3);

const browser = await chromium.launch({
  executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true,
});
for (const [name, url] of sites) {
  if (only.length && !only.includes(name)) continue;
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1, colorScheme: 'light',
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
  });
  const page = await context.newPage();
  try {
    await page.goto(url, { waitUntil: 'load', timeout: 30000 });
    await page.waitForTimeout(2500);
    await page.screenshot({ path: `${out}/${name}-hero.jpg`, type: 'jpeg', quality: 80 });
    // Scroll through so that lazy images and scroll-triggered sections appear.
    const height = await page.evaluate(() => document.documentElement.scrollHeight);
    for (let y = 0; y < Math.min(height, 9000); y += 600) {
      await page.evaluate((y) => window.scrollTo(0, y), y);
      await page.waitForTimeout(250);
    }
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.waitForTimeout(800);
    const full = await page.evaluate(() => document.documentElement.scrollHeight);
    await page.screenshot({
      path: `${out}/${name}-page.jpg`, type: 'jpeg', quality: 70, fullPage: true,
      clip: { x: 0, y: 0, width: 1440, height: Math.min(full, 7200) },
    });
    console.log('ok', name, full);
  } catch (error) {
    console.log('failed', name, error.message.split('\n')[0]);
  }
  await context.close();
}
await browser.close();
