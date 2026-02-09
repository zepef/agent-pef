/**
 * CDP (Chrome DevTools Protocol) WebSocket shim
 *
 * Implements a subset of the CDP protocol over WebSocket, translating commands
 * to Cloudflare Browser Rendering binding calls (Puppeteer interface).
 *
 * Authentication: Pass secret via Authorization header (Bearer) or query param
 * `?secret=<secret>` on WebSocket connect (query param needed for WS clients).
 * This route is intentionally NOT protected by Cloudflare Access.
 *
 * Supported CDP domains:
 * - Browser: getVersion, close
 * - Target: createTarget, closeTarget, getTargets
 * - Page: navigate, reload, getFrameTree, captureScreenshot, getLayoutMetrics
 * - Runtime: evaluate
 * - DOM: getDocument, querySelector, querySelectorAll, getOuterHTML, getAttributes
 * - Input: dispatchMouseEvent, dispatchKeyEvent, insertText
 * - Network: enable, disable, setCacheDisabled
 * - Emulation: setDeviceMetricsOverride, setUserAgentOverride
 */
import { Hono, type Context } from 'hono';
import type { AppEnv } from '../../types';
import { extractCDPSecret, timingSafeEqual } from './utils';
import { initCDPSession } from './session';

const SUPPORTED_METHODS = [
  // Browser
  'Browser.getVersion',
  'Browser.close',
  // Target
  'Target.createTarget',
  'Target.closeTarget',
  'Target.getTargets',
  'Target.attachToTarget',
  // Page
  'Page.navigate',
  'Page.reload',
  'Page.captureScreenshot',
  'Page.getFrameTree',
  'Page.getLayoutMetrics',
  'Page.bringToFront',
  'Page.setContent',
  'Page.printToPDF',
  'Page.addScriptToEvaluateOnNewDocument',
  'Page.removeScriptToEvaluateOnNewDocument',
  'Page.handleJavaScriptDialog',
  'Page.stopLoading',
  'Page.getNavigationHistory',
  'Page.navigateToHistoryEntry',
  'Page.setBypassCSP',
  // Runtime
  'Runtime.evaluate',
  'Runtime.callFunctionOn',
  'Runtime.getProperties',
  'Runtime.releaseObject',
  'Runtime.releaseObjectGroup',
  // DOM
  'DOM.getDocument',
  'DOM.querySelector',
  'DOM.querySelectorAll',
  'DOM.getOuterHTML',
  'DOM.getAttributes',
  'DOM.setAttributeValue',
  'DOM.focus',
  'DOM.getBoxModel',
  'DOM.scrollIntoViewIfNeeded',
  'DOM.removeNode',
  'DOM.setNodeValue',
  'DOM.setFileInputFiles',
  // Input
  'Input.dispatchMouseEvent',
  'Input.dispatchKeyEvent',
  'Input.insertText',
  // Network
  'Network.enable',
  'Network.disable',
  'Network.setCacheDisabled',
  'Network.setExtraHTTPHeaders',
  'Network.setCookie',
  'Network.setCookies',
  'Network.getCookies',
  'Network.deleteCookies',
  'Network.clearBrowserCookies',
  'Network.setUserAgentOverride',
  // Fetch (Request Interception)
  'Fetch.enable',
  'Fetch.disable',
  'Fetch.continueRequest',
  'Fetch.fulfillRequest',
  'Fetch.failRequest',
  'Fetch.getResponseBody',
  // Emulation
  'Emulation.setDeviceMetricsOverride',
  'Emulation.clearDeviceMetricsOverride',
  'Emulation.setUserAgentOverride',
  'Emulation.setGeolocationOverride',
  'Emulation.clearGeolocationOverride',
  'Emulation.setTimezoneOverride',
  'Emulation.setTouchEmulationEnabled',
  'Emulation.setEmulatedMedia',
  'Emulation.setDefaultBackgroundColorOverride',
];

const cdp = new Hono<AppEnv>();

/**
 * Verify CDP secret and BROWSER binding. Returns error response or null if valid.
 */
function verifyCDPAuth(c: Context<AppEnv>): Response | null {
  const providedSecret = extractCDPSecret(c);
  const expectedSecret = c.env.CDP_SECRET;

  if (!expectedSecret) {
    return c.json({
      error: 'CDP endpoint not configured',
      hint: 'Set CDP_SECRET via: wrangler secret put CDP_SECRET',
    }, 503) as unknown as Response;
  }

  if (!providedSecret || !timingSafeEqual(providedSecret, expectedSecret)) {
    return c.json({ error: 'Unauthorized' }, 401) as unknown as Response;
  }

  if (!c.env.BROWSER) {
    return c.json({
      error: 'Browser Rendering not configured',
      hint: 'Add browser binding to wrangler.jsonc',
    }, 503) as unknown as Response;
  }

  return null;
}

/**
 * Build WebSocket URL from the current request URL and secret.
 */
function buildWsUrl(c: Context<AppEnv>): string {
  const url = new URL(c.req.url);
  const secret = extractCDPSecret(c)!;
  const wsProtocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
  return `${wsProtocol}//${url.host}/cdp?secret=${encodeURIComponent(secret)}`;
}

/**
 * GET /cdp - WebSocket upgrade endpoint
 *
 * Connect with: ws://host/cdp?secret=<CDP_SECRET>
 */
cdp.get('/', async (c) => {
  // Check for WebSocket upgrade
  const upgradeHeader = c.req.header('Upgrade');
  if (upgradeHeader?.toLowerCase() !== 'websocket') {
    return c.json({
      error: 'WebSocket upgrade required',
      hint: 'Connect via WebSocket: ws://host/cdp?secret=<CDP_SECRET>',
      supported_methods: SUPPORTED_METHODS,
    });
  }

  const authError = verifyCDPAuth(c);
  if (authError) return authError;

  // Create WebSocket pair
  const webSocketPair = new WebSocketPair();
  const [client, server] = Object.values(webSocketPair);

  // Accept the WebSocket
  server.accept();

  // Initialize CDP session asynchronously
  initCDPSession(server, c.env).catch((err) => {
    console.error('[CDP] Failed to initialize session:', err);
    server.close(1011, 'Failed to initialize browser session');
  });

  return new Response(null, {
    status: 101,
    webSocket: client,
  });
});

/**
 * GET /json/version - CDP discovery endpoint
 */
cdp.get('/json/version', async (c) => {
  const authError = verifyCDPAuth(c);
  if (authError) return authError;

  return c.json({
    'Browser': 'Cloudflare-Browser-Rendering/1.0',
    'Protocol-Version': '1.3',
    'User-Agent': 'Mozilla/5.0 Cloudflare Browser Rendering',
    'V8-Version': 'cloudflare',
    'WebKit-Version': 'cloudflare',
    'webSocketDebuggerUrl': buildWsUrl(c),
  });
});

/**
 * GET /json/list - List available targets (tabs)
 */
cdp.get('/json/list', async (c) => {
  const authError = verifyCDPAuth(c);
  if (authError) return authError;

  return c.json([
    {
      'description': '',
      'devtoolsFrontendUrl': '',
      'id': 'cloudflare-browser',
      'title': 'Cloudflare Browser Rendering',
      'type': 'page',
      'url': 'about:blank',
      'webSocketDebuggerUrl': buildWsUrl(c),
    },
  ]);
});

/**
 * GET /json - Alias for /json/list (some clients use this)
 */
cdp.get('/json', async (c) => {
  const authError = verifyCDPAuth(c);
  if (authError) return authError;

  return c.json([
    {
      'description': '',
      'devtoolsFrontendUrl': '',
      'id': 'cloudflare-browser',
      'title': 'Cloudflare Browser Rendering',
      'type': 'page',
      'url': 'about:blank',
      'webSocketDebuggerUrl': buildWsUrl(c),
    },
  ]);
});

export { cdp };
