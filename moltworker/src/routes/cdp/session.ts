import puppeteer from '@cloudflare/puppeteer';
import type { MoltbotEnv } from '../../types';
import type { CDPRequest, CDPSession } from './types';
import { sendResponse, sendError, sendEvent } from './utils';
import { handleBrowser } from './browser';
import { handleTarget } from './target';
import { handlePage } from './page';
import { handleRuntime } from './runtime';
import { handleDOM } from './dom';
import { handleInput } from './input';
import { handleNetwork } from './network';
import { handleEmulation } from './emulation';
import { handleFetch } from './fetch-handler';

/**
 * Initialize a CDP session for a WebSocket connection
 */
export async function initCDPSession(ws: WebSocket, env: MoltbotEnv): Promise<void> {
  let session: CDPSession | null = null;

  try {
    // Launch browser
    const browser = await puppeteer.launch(env.BROWSER!);
    const page = await browser.newPage();
    const targetId = crypto.randomUUID();

    session = {
      browser,
      pages: new Map([[targetId, page]]),
      defaultTargetId: targetId,
      nodeIdCounter: 1,
      nodeMap: new Map(),
      objectIdCounter: 1,
      objectMap: new Map(),
      scriptsToEvaluateOnNewDocument: new Map(),
      extraHTTPHeaders: new Map(),
      requestInterceptionEnabled: false,
      pendingRequests: new Map(),
    };

    // Send initial target created event
    sendEvent(ws, 'Target.targetCreated', {
      targetInfo: {
        targetId,
        type: 'page',
        title: '',
        url: 'about:blank',
        attached: true,
      },
    });

    console.log('[CDP] Session initialized, targetId:', targetId);
  } catch (err) {
    console.error('[CDP] Browser launch failed:', err);
    ws.close(1011, 'Browser launch failed');
    return;
  }

  // Handle incoming messages
  ws.addEventListener('message', async (event) => {
    if (!session) return;

    let request: CDPRequest;
    try {
      request = JSON.parse(event.data as string);
    } catch {
      console.error('[CDP] Invalid JSON received');
      return;
    }

    console.log('[CDP] Request:', request.method, request.params);

    try {
      const result = await handleCDPMethod(session, request.method, request.params || {}, ws);
      sendResponse(ws, request.id, result);
    } catch (err) {
      console.error('[CDP] Method error:', request.method, err);
      sendError(ws, request.id, -32000, err instanceof Error ? err.message : 'Unknown error');
    }
  });

  // Handle close
  ws.addEventListener('close', async () => {
    console.log('[CDP] WebSocket closed, cleaning up');
    if (session) {
      try {
        await session.browser.close();
      } catch (err) {
        console.error('[CDP] Error closing browser:', err);
      }
    }
  });

  ws.addEventListener('error', (event) => {
    console.error('[CDP] WebSocket error:', event);
  });
}

/**
 * Handle a CDP method call - routes to the appropriate domain handler
 */
async function handleCDPMethod(
  session: CDPSession,
  method: string,
  params: Record<string, unknown>,
  ws: WebSocket
): Promise<unknown> {
  const [domain, command] = method.split('.');

  // Get the current page (use targetId from params or default)
  const targetId = (params.targetId as string) || session.defaultTargetId;
  const page = session.pages.get(targetId);

  switch (domain) {
    case 'Browser':
      return handleBrowser(session, command, params);

    case 'Target':
      return handleTarget(session, command, params, ws);

    case 'Page':
      if (!page) throw new Error(`Target not found: ${targetId}`);
      return handlePage(session, page, command, params, ws);

    case 'Runtime':
      if (!page) throw new Error(`Target not found: ${targetId}`);
      return handleRuntime(session, page, command, params);

    case 'DOM':
      if (!page) throw new Error(`Target not found: ${targetId}`);
      return handleDOM(session, page, command, params);

    case 'Input':
      if (!page) throw new Error(`Target not found: ${targetId}`);
      return handleInput(page, command, params);

    case 'Network':
      return handleNetwork(session, page, command, params);

    case 'Emulation':
      if (!page) throw new Error(`Target not found: ${targetId}`);
      return handleEmulation(page, command, params);

    case 'Fetch':
      if (!page) throw new Error(`Target not found: ${targetId}`);
      return handleFetch(session, page, command, params, ws);

    default:
      throw new Error(`Unknown domain: ${domain}`);
  }
}
