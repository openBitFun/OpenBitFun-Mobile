import puppeteer from 'puppeteer-core';
import { existsSync } from 'node:fs';
export function launchBrowser() {
 const executablePath = [process.env.CHROME_PATH, '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', '/usr/bin/google-chrome', '/usr/bin/chromium'].find(p => p && existsSync(p));
 if (!executablePath) throw new Error('Install Chrome or set CHROME_PATH for native WebView tests.');
 return puppeteer.launch({executablePath,headless:true,args:['--no-sandbox']});
}
