import type { CDPSession } from './types';

/**
 * Browser domain handlers
 */
export async function handleBrowser(
  session: CDPSession,
  command: string,
  _params: Record<string, unknown>
): Promise<unknown> {
  switch (command) {
    case 'getVersion':
      return {
        protocolVersion: '1.3',
        product: 'Cloudflare-Browser-Rendering',
        revision: 'cloudflare',
        userAgent: 'Mozilla/5.0 Cloudflare Browser Rendering',
        jsVersion: 'V8',
      };

    case 'close':
      await session.browser.close();
      return {};

    default:
      throw new Error(`Unknown Browser method: ${command}`);
  }
}
