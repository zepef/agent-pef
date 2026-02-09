import type { Page } from '@cloudflare/puppeteer';
import type { CDPSession } from './types';
import { sendEvent } from './utils';

/**
 * Fetch domain handlers (request interception)
 */
export async function handleFetch(
  session: CDPSession,
  page: Page,
  command: string,
  params: Record<string, unknown>,
  ws: WebSocket
): Promise<unknown> {
  switch (command) {
    case 'enable': {
      const patterns = params.patterns as Array<{ urlPattern?: string; requestStage?: string }> | undefined;

      session.requestInterceptionEnabled = true;

      // Set up request interception
      await page.setRequestInterception(true);

      page.on('request', async (request) => {
        if (!session.requestInterceptionEnabled) {
          await request.continue();
          return;
        }

        const requestId = crypto.randomUUID();

        // Check if request matches patterns
        let shouldIntercept = !patterns || patterns.length === 0;
        if (patterns) {
          for (const pattern of patterns) {
            if (!pattern.urlPattern || request.url().match(pattern.urlPattern)) {
              shouldIntercept = true;
              break;
            }
          }
        }

        if (shouldIntercept) {
          // Store the request for later handling
          session.pendingRequests.set(requestId, {
            request: request as unknown as Request,
            resolve: () => {},
          });

          // Send Fetch.requestPaused event
          sendEvent(ws, 'Fetch.requestPaused', {
            requestId,
            request: {
              url: request.url(),
              method: request.method(),
              headers: request.headers(),
              postData: request.postData(),
            },
            frameId: session.defaultTargetId,
            resourceType: request.resourceType(),
          });
        } else {
          await request.continue();
        }
      });

      return {};
    }

    case 'disable': {
      session.requestInterceptionEnabled = false;
      await page.setRequestInterception(false);
      return {};
    }

    case 'continueRequest': {
      const requestId = params.requestId as string;
      const url = params.url as string | undefined;
      const method = params.method as string | undefined;
      const postData = params.postData as string | undefined;
      const headers = params.headers as Array<{ name: string; value: string }> | undefined;

      const pending = session.pendingRequests.get(requestId);
      if (!pending) {
        throw new Error(`Request not found: ${requestId}`);
      }

      const request = pending.request as unknown as { continue: (opts?: Record<string, unknown>) => Promise<void> };

      const overrides: Record<string, unknown> = {};
      if (url) overrides.url = url;
      if (method) overrides.method = method;
      if (postData) overrides.postData = postData;
      if (headers) {
        overrides.headers = headers.reduce((acc, h) => {
          acc[h.name] = h.value;
          return acc;
        }, {} as Record<string, string>);
      }

      await request.continue(Object.keys(overrides).length > 0 ? overrides : undefined);
      session.pendingRequests.delete(requestId);

      return {};
    }

    case 'fulfillRequest': {
      const requestId = params.requestId as string;
      const responseCode = params.responseCode as number;
      const responseHeaders = params.responseHeaders as Array<{ name: string; value: string }> | undefined;
      const body = params.body as string | undefined;

      const pending = session.pendingRequests.get(requestId);
      if (!pending) {
        throw new Error(`Request not found: ${requestId}`);
      }

      const request = pending.request as unknown as { respond: (opts: Record<string, unknown>) => Promise<void> };

      const headers: Record<string, string> = {};
      if (responseHeaders) {
        for (const h of responseHeaders) {
          headers[h.name] = h.value;
        }
      }

      await request.respond({
        status: responseCode,
        headers,
        body: body ? Buffer.from(body, 'base64') : undefined,
      });

      session.pendingRequests.delete(requestId);

      return {};
    }

    case 'failRequest': {
      const requestId = params.requestId as string;
      const errorReason = params.errorReason as string;

      const pending = session.pendingRequests.get(requestId);
      if (!pending) {
        throw new Error(`Request not found: ${requestId}`);
      }

      const request = pending.request as unknown as { abort: (reason?: string) => Promise<void> };

      // Map CDP error reasons to Puppeteer abort reasons
      const abortReason = errorReason.toLowerCase().includes('access') ? 'accessdenied' :
                         errorReason.toLowerCase().includes('address') ? 'addressunreachable' :
                         errorReason.toLowerCase().includes('blocked') ? 'blockedbyclient' :
                         errorReason.toLowerCase().includes('connection') ? 'connectionfailed' :
                         errorReason.toLowerCase().includes('timeout') ? 'timedout' :
                         'failed';

      await request.abort(abortReason);
      session.pendingRequests.delete(requestId);

      return {};
    }

    case 'getResponseBody': {
      // This would need to store response bodies, which we're not currently doing
      // Return empty for now
      return { body: '', base64Encoded: false };
    }

    default:
      throw new Error(`Unknown Fetch method: ${command}`);
  }
}
