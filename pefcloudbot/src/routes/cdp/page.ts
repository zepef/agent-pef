import type { Page } from '@cloudflare/puppeteer';
import type { CDPSession } from './types';
import { sendEvent } from './utils';

/**
 * Page domain handlers
 */
export async function handlePage(
  session: CDPSession,
  page: Page,
  command: string,
  params: Record<string, unknown>,
  ws: WebSocket
): Promise<unknown> {
  switch (command) {
    case 'navigate': {
      const url = params.url as string;
      if (!url) throw new Error('url is required');

      const response = await page.goto(url, {
        waitUntil: 'load',
      });

      sendEvent(ws, 'Page.frameNavigated', {
        frame: {
          id: session.defaultTargetId,
          url: page.url(),
          securityOrigin: new URL(page.url()).origin,
          mimeType: 'text/html',
        },
      });

      sendEvent(ws, 'Page.loadEventFired', {
        timestamp: Date.now() / 1000,
      });

      return {
        frameId: session.defaultTargetId,
        loaderId: crypto.randomUUID(),
        errorText: response?.ok() ? undefined : 'Navigation failed',
      };
    }

    case 'reload': {
      await page.reload();
      return {};
    }

    case 'getFrameTree': {
      return {
        frameTree: {
          frame: {
            id: session.defaultTargetId,
            loaderId: crypto.randomUUID(),
            url: page.url(),
            securityOrigin: page.url() ? new URL(page.url()).origin : '',
            mimeType: 'text/html',
          },
          childFrames: [],
        },
      };
    }

    case 'captureScreenshot': {
      const format = (params.format as string) || 'png';
      const quality = params.quality as number | undefined;
      const clip = params.clip as { x: number; y: number; width: number; height: number } | undefined;

      const data = await page.screenshot({
        type: format as 'png' | 'jpeg' | 'webp',
        encoding: 'base64',
        quality: format === 'jpeg' ? quality : undefined,
        clip: clip,
        fullPage: params.fullPage as boolean | undefined,
      });

      return { data };
    }

    case 'getLayoutMetrics': {
      const metrics = await page.evaluate(() => ({
        width: document.documentElement.scrollWidth,
        height: document.documentElement.scrollHeight,
        clientWidth: document.documentElement.clientWidth,
        clientHeight: document.documentElement.clientHeight,
      }));

      return {
        layoutViewport: {
          pageX: 0,
          pageY: 0,
          clientWidth: metrics.clientWidth,
          clientHeight: metrics.clientHeight,
        },
        visualViewport: {
          offsetX: 0,
          offsetY: 0,
          pageX: 0,
          pageY: 0,
          clientWidth: metrics.clientWidth,
          clientHeight: metrics.clientHeight,
          scale: 1,
        },
        contentSize: {
          x: 0,
          y: 0,
          width: metrics.width,
          height: metrics.height,
        },
      };
    }

    case 'bringToFront':
      await page.bringToFront();
      return {};

    case 'setContent': {
      const html = params.html as string;
      if (!html) throw new Error('html is required');

      await page.setContent(html, {
        waitUntil: (params.waitUntil as 'load' | 'domcontentloaded' | 'networkidle0' | 'networkidle2') || 'load',
      });

      return {};
    }

    case 'printToPDF': {
      const options: Parameters<typeof page.pdf>[0] = {};

      if (params.landscape) options.landscape = params.landscape as boolean;
      if (params.displayHeaderFooter) options.displayHeaderFooter = params.displayHeaderFooter as boolean;
      if (params.printBackground) options.printBackground = params.printBackground as boolean;
      if (params.scale) options.scale = params.scale as number;
      if (params.paperWidth) options.width = `${params.paperWidth}in`;
      if (params.paperHeight) options.height = `${params.paperHeight}in`;
      if (params.marginTop) options.margin = { ...options.margin, top: `${params.marginTop}in` };
      if (params.marginBottom) options.margin = { ...options.margin, bottom: `${params.marginBottom}in` };
      if (params.marginLeft) options.margin = { ...options.margin, left: `${params.marginLeft}in` };
      if (params.marginRight) options.margin = { ...options.margin, right: `${params.marginRight}in` };
      if (params.pageRanges) options.pageRanges = params.pageRanges as string;
      if (params.headerTemplate) options.headerTemplate = params.headerTemplate as string;
      if (params.footerTemplate) options.footerTemplate = params.footerTemplate as string;
      if (params.preferCSSPageSize) options.preferCSSPageSize = params.preferCSSPageSize as boolean;

      const buffer = await page.pdf(options);
      // Convert to base64
      const data = typeof buffer === 'string' ? buffer : Buffer.from(buffer).toString('base64');

      return { data };
    }

    case 'addScriptToEvaluateOnNewDocument': {
      const source = params.source as string;
      if (!source) throw new Error('source is required');

      const identifier = crypto.randomUUID();
      session.scriptsToEvaluateOnNewDocument.set(identifier, source);

      // Add to the page via evaluateOnNewDocument
      await page.evaluateOnNewDocument(source);

      return { identifier };
    }

    case 'removeScriptToEvaluateOnNewDocument': {
      const identifier = params.identifier as string;
      session.scriptsToEvaluateOnNewDocument.delete(identifier);
      // Note: Can't actually remove already-added scripts in Puppeteer
      return {};
    }

    case 'handleJavaScriptDialog': {
      const accept = params.accept as boolean;
      const promptText = params.promptText as string | undefined;

      // Puppeteer auto-handles dialogs, but we can configure the page
      page.on('dialog', async (dialog) => {
        if (accept) {
          await dialog.accept(promptText);
        } else {
          await dialog.dismiss();
        }
      });

      return {};
    }

    case 'stopLoading': {
      await page.evaluate(() => window.stop());
      return {};
    }

    case 'getNavigationHistory': {
      const history = await page.evaluate(() => ({
        currentIndex: window.history.length - 1,
        entries: [{
          id: 0,
          url: window.location.href,
          userTypedURL: window.location.href,
          title: document.title,
          transitionType: 'typed',
        }],
      }));

      return history;
    }

    case 'navigateToHistoryEntry': {
      const entryId = params.entryId as number;
      // Simple implementation - just go back/forward
      await page.evaluate((id: number) => {
        const delta = id - (window.history.length - 1);
        window.history.go(delta);
      }, entryId);

      return {};
    }

    case 'setBypassCSP': {
      const enabled = params.enabled as boolean;
      await page.setBypassCSP(enabled);
      return {};
    }

    case 'enable':
    case 'disable':
      // No-op, events always enabled
      return {};

    default:
      throw new Error(`Unknown Page method: ${command}`);
  }
}
