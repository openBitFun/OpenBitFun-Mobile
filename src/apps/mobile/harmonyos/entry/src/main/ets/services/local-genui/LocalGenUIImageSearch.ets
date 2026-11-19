import { http } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { RemoteLogger } from '../RemoteLogger';

/**
 * Photo search for Local GenUI apps, the phone counterpart of the desktop
 * `image.search` provider (src/apps/desktop/src/api/generative_ui_api.rs):
 * 360 and Baidu image search together, then Wikipedia and Wikimedia Commons
 * when neither returns anything, at most four photos, within 16 seconds.
 *
 * The page has no network access of its own. Search results are handed to it
 * as `<ROOT><id>` addresses that LocalGenUIWebSurface answers, and the host
 * only fetches photos it found itself in this process (or already cached), so
 * a generated app cannot use the address to reach anything else.
 *
 * Phone differences from the desktop provider: a record contributes one photo
 * (its first image field, thumbnails first), `link` is not read because 360
 * uses it for the result page, and Commons answers use the sized thumbnail
 * instead of the original upload. Answers are remembered per query on the
 * phone: the domestic endpoints are unofficial and rate-limit repeated searches.
 */
export const LOCAL_GENUI_PHOTO_ROOT: string = 'https://genui-assets.openbitfun.invalid/photo/';

const SO_IMAGE_API: string = 'https://image.so.com/j';
const BAIDU_IMAGE_API: string = 'https://image.baidu.com/search/acjson';
const WIKIPEDIA_SUMMARY: string = 'https://en.wikipedia.org/api/rest_v1/page/summary/';
const WIKIMEDIA_API: string = 'https://commons.wikimedia.org/w/api.php';
const USER_AGENT: string = 'OpenBitFun/1.0 (GenUI host provider)';
const IMAGE_KEYS: string[] = ['thumb', 'thumburl', 'thumbURL', 'middleURL', 'src', 'img', 'url', 'objURL', 'hoverURL'];
const MAX_RESULTS: number = 4;
const MAX_COLLECTED: number = 8;
const MAX_ISSUED: number = 500;
const MAX_PHOTO_BYTES: number = 4 * 1024 * 1024;
const DOMESTIC_TIMEOUT_MS: number = 6000;
const OPEN_TIMEOUT_MS: number = 8000;
const SEARCH_TIMEOUT_MS: number = 16000;
const PHOTO_ID: RegExp = /^[0-9a-f]{16}$/;
/** Answered queries kept on the phone, so reopening an app does not search again. */
const MAX_CACHED_QUERIES: number = 300;

/** Stable 64-bit FNV-1a style id of an upstream URL, as 16 hex characters. */
function photoId(url: string): string {
  let a = 0x811c9dc5;
  let b = 0x01000193 ^ 0x5bd1e995;
  for (let i = 0; i < url.length; i++) {
    const c = url.charCodeAt(i);
    a = Math.imul(a ^ c, 0x01000193) >>> 0;
    b = Math.imul(b ^ c, 0x5bd1e995) >>> 0;
  }
  return a.toString(16).padStart(8, '0') + b.toString(16).padStart(8, '0');
}

function acceptable(url: string): boolean {
  const lower = url.toLowerCase();
  return (lower.startsWith('https://') || lower.startsWith('http://')) &&
    lower.indexOf('.svg') < 0 && lower.indexOf('logo') < 0 && lower.indexOf('icon') < 0 && url.length <= 2048;
}

/** One photo per record, searched depth-first like the desktop collector. */
function collect(value: Object | null | undefined, images: string[]): void {
  if (value === null || value === undefined || images.length >= MAX_COLLECTED) {
    return;
  }
  if (Array.isArray(value)) {
    for (const item of value as Object[]) {
      collect(item, images);
    }
    return;
  }
  if (typeof value !== 'object') {
    return;
  }
  const record = value as Record<string, Object>;
  for (const key of IMAGE_KEYS) {
    const candidate = record[key];
    if (typeof candidate === 'string') {
      const url = (candidate as string).trim();
      if (acceptable(url)) {
        if (images.indexOf(url) < 0) {
          images.push(url);
        }
        break;
      }
    }
  }
  for (const key of Object.keys(record)) {
    if (images.length >= MAX_COLLECTED) {
      return;
    }
    const child = record[key];
    if (child !== null && typeof child === 'object') {
      collect(child, images);
    }
  }
}

function withTimeout<T>(work: Promise<T>, ms: number, fallback: T): Promise<T> {
  return new Promise<T>((resolve: (value: T) => void) => {
    const timer = setTimeout(() => resolve(fallback), ms);
    work.then((value: T) => {
      clearTimeout(timer);
      resolve(value);
    }).catch(() => {
      clearTimeout(timer);
      resolve(fallback);
    });
  });
}

export class LocalGenUIImageSearch {
  private readonly directory: string;
  /** Photo id -> upstream URL for photos this process found. */
  private readonly issued: Map<string, string> = new Map<string, string>();
  private readonly inflight: Map<string, Promise<ArrayBuffer | undefined>> = new Map<string, Promise<ArrayBuffer | undefined>>();
  private readonly searches: Map<string, Promise<string[]>> = new Map<string, Promise<string[]>>();
  private answers?: Map<string, string[]>;

  constructor(filesDir: string) {
    this.directory = `${filesDir}/local-genui/photos`;
  }

  /** The query the desktop provider accepts: 2 to 200 characters, trimmed. */
  static queryOf(raw: string): string {
    const query = (raw || '').trim();
    const length = Array.from(query).length;
    return length >= 2 && length <= 200 ? query : '';
  }

  /** The photo id an address names, or '' when it is not a served photo. */
  static photoIdOf(url: string): string {
    if (!url.startsWith(LOCAL_GENUI_PHOTO_ROOT)) {
      return '';
    }
    const id = url.substring(LOCAL_GENUI_PHOTO_ROOT.length);
    return PHOTO_ID.test(id) ? id : '';
  }

  /** Host addresses of up to four photos for the query. */
  async search(raw: string): Promise<string[]> {
    const query = LocalGenUIImageSearch.queryOf(raw);
    if (query.length === 0) {
      return [];
    }
    const remembered = this.remembered().get(query);
    if (remembered && remembered.length > 0) {
      return remembered.map((url: string): string => this.issue(url));
    }
    let running = this.searches.get(query);
    if (!running) {
      running = withTimeout(this.searchSources(query), SEARCH_TIMEOUT_MS, [] as string[]);
      this.searches.set(query, running);
    }
    const found = await running;
    this.searches.delete(query);
    RemoteLogger.info(`local genui image search found ${found.length}`);
    if (found.length > 0) {
      this.remember(query, found);
    }
    return found.map((url: string): string => this.issue(url));
  }

  private answersFile(): string {
    return `${this.directory}/queries.json`;
  }

  private remembered(): Map<string, string[]> {
    if (this.answers) {
      return this.answers;
    }
    const answers = new Map<string, string[]>();
    try {
      const file = this.answersFile();
      if (fs.accessSync(file)) {
        const rows = JSON.parse(fs.readTextSync(file)) as Object;
        if (Array.isArray(rows)) {
          for (const row of rows as Object[]) {
            const entry = row as Record<string, Object>;
            const query = entry['q'];
            const urls = entry['u'];
            if (typeof query === 'string' && Array.isArray(urls)) {
              answers.set(query as string, (urls as Object[]).filter((url: Object): boolean => typeof url === 'string' &&
                acceptable(url as string)) as string[]);
            }
          }
        }
      }
    } catch (_err) {
      // A damaged answer cache only costs new searches.
    }
    this.answers = answers;
    return answers;
  }

  private remember(query: string, urls: string[]): void {
    const answers = this.remembered();
    answers.delete(query);
    answers.set(query, urls);
    while (answers.size > MAX_CACHED_QUERIES) {
      const oldest = answers.keys().next();
      if (oldest.done) break;
      answers.delete(oldest.value);
    }
    const rows: Record<string, Object>[] = [];
    answers.forEach((value: string[], key: string) => {
      const row: Record<string, Object> = { 'q': key, 'u': value };
      rows.push(row);
    });
    const file = this.answersFile();
    const temporary = `${file}.${Date.now()}.tmp`;
    try {
      if (!fs.accessSync(this.directory)) {
        fs.mkdirSync(this.directory, true);
      }
      const handle = fs.openSync(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(handle.fd, JSON.stringify(rows));
      } finally {
        fs.closeSync(handle);
      }
      fs.renameSync(temporary, file);
    } catch (_err) {
      try { fs.unlinkSync(temporary); } catch (_ignored) { /* derived data */ }
    }
  }

  private async searchSources(query: string): Promise<string[]> {
    const domestic = await Promise.all([this.so(query), this.baidu(query)]);
    const images: string[] = [];
    for (const url of domestic[0].concat(domestic[1])) {
      if (images.indexOf(url) < 0) {
        images.push(url);
      }
    }
    if (images.length > 0) {
      return images.slice(0, MAX_RESULTS);
    }
    return this.open(query);
  }

  private issue(url: string): string {
    const id = photoId(url);
    if (!this.issued.has(id) && this.issued.size >= MAX_ISSUED) {
      const oldest = this.issued.keys().next();
      if (!oldest.done) {
        this.issued.delete(oldest.value);
      }
    }
    this.issued.set(id, url);
    return LOCAL_GENUI_PHOTO_ROOT + id;
  }

  private async so(query: string): Promise<string[]> {
    const q = encodeURIComponent(query);
    const value = await this.json(`${SO_IMAGE_API}?q=${q}&pn=0&sn=0&pd=1&correct=${q}`, DOMESTIC_TIMEOUT_MS);
    const images: string[] = [];
    collect(value, images);
    return images.slice(0, MAX_RESULTS);
  }

  private async baidu(query: string): Promise<string[]> {
    const value = await this.json(`${BAIDU_IMAGE_API}?tn=resultjson_com&word=${encodeURIComponent(query)}&ie=utf-8&pn=0&rn=10`,
      DOMESTIC_TIMEOUT_MS);
    const images: string[] = [];
    collect(value, images);
    return images.slice(0, MAX_RESULTS);
  }

  /** Wikipedia summary and Commons search, together, as the desktop open fallback. */
  private async open(query: string): Promise<string[]> {
    const commonsQuery = `action=query&format=json&formatversion=2&generator=search&gsrsearch=${encodeURIComponent(query)}` +
      '&gsrnamespace=6&gsrlimit=8&prop=imageinfo&iiprop=url%7Cmime&iiurlwidth=960';
    const results = await Promise.all([
      this.json(WIKIPEDIA_SUMMARY + encodeURIComponent(query), OPEN_TIMEOUT_MS),
      this.json(`${WIKIMEDIA_API}?${commonsQuery}`, OPEN_TIMEOUT_MS)
    ]);
    const images: string[] = [];
    const summary = results[0];
    if (summary !== undefined && typeof summary === 'object') {
      const thumbnail = (summary as Record<string, Object>)['thumbnail'];
      if (thumbnail !== undefined && typeof thumbnail === 'object') {
        const source = (thumbnail as Record<string, Object>)['source'];
        if (typeof source === 'string' && acceptable(source as string)) {
          images.push(source as string);
        }
      }
    }
    collect(results[1], images);
    return images.slice(0, MAX_RESULTS);
  }

  private async json(url: string, timeoutMs: number): Promise<Object | undefined> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        header: { 'User-Agent': USER_AGENT },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs
      });
      if (response.responseCode !== 200 || typeof response.result !== 'string') {
        return undefined;
      }
      return JSON.parse(response.result as string) as Object;
    } catch (_err) {
      return undefined;
    } finally {
      request.destroy();
    }
  }

  /** Image bytes for a served photo, from the cache or its upstream address. */
  async picture(url: string): Promise<ArrayBuffer | undefined> {
    const id = LocalGenUIImageSearch.photoIdOf(url);
    if (id.length === 0) {
      return undefined;
    }
    const running = this.inflight.get(id);
    if (running) {
      return running;
    }
    const work = this.load(id).finally(() => { this.inflight.delete(id); });
    this.inflight.set(id, work);
    return work;
  }

  private async load(id: string): Promise<ArrayBuffer | undefined> {
    const file = `${this.directory}/${id}.img`;
    try {
      if (fs.accessSync(file)) {
        const handle = fs.openSync(file, fs.OpenMode.READ_ONLY);
        try {
          const buffer = new ArrayBuffer(fs.statSync(file).size);
          fs.readSync(handle.fd, buffer);
          return buffer;
        } finally {
          fs.closeSync(handle);
        }
      }
    } catch (_err) {
      // A damaged cache entry is fetched again.
    }
    const upstream = this.issued.get(id);
    if (!upstream) {
      return undefined;
    }
    const bytes = await this.download(upstream);
    if (bytes) {
      this.store(file, bytes);
    }
    return bytes;
  }

  private async download(url: string): Promise<ArrayBuffer | undefined> {
    const request = http.createHttp();
    try {
      const header: Record<string, string> = { 'User-Agent': USER_AGENT };
      if (url.indexOf('baidu.com') >= 0 || url.indexOf('bdimg.com') >= 0) {
        header['Referer'] = 'https://image.baidu.com/';
      }
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        header,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 8000,
        readTimeout: 15000
      });
      const body = response.result;
      const type = String((response.header as Record<string, Object>)?.['content-type'] ??
        (response.header as Record<string, Object>)?.['Content-Type'] ?? '');
      if (response.responseCode !== 200 || !(body instanceof ArrayBuffer) || body.byteLength === 0 ||
        body.byteLength > MAX_PHOTO_BYTES || (type.length > 0 && !type.toLowerCase().startsWith('image/'))) {
        RemoteLogger.warn(`local genui photo unavailable status=${response.responseCode}`);
        return undefined;
      }
      return body;
    } catch (err) {
      RemoteLogger.warn(`local genui photo fetch failed: ${err instanceof Error ? err.message : String(err)}`);
      return undefined;
    } finally {
      request.destroy();
    }
  }

  private store(file: string, bytes: ArrayBuffer): void {
    const temporary = `${file}.${Date.now()}.tmp`;
    try {
      if (!fs.accessSync(this.directory)) {
        fs.mkdirSync(this.directory, true);
      }
      const handle = fs.openSync(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(handle.fd, bytes);
      } finally {
        fs.closeSync(handle);
      }
      fs.renameSync(temporary, file);
    } catch (_err) {
      try { fs.unlinkSync(temporary); } catch (_ignored) { /* derived data */ }
    }
  }
}
