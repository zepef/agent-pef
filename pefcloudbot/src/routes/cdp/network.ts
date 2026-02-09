import type { Page } from '@cloudflare/puppeteer';
import type { CDPSession } from './types';

/**
 * Network domain handlers
 */
export async function handleNetwork(
  session: CDPSession,
  page: Page | undefined,
  command: string,
  params: Record<string, unknown>
): Promise<unknown> {
  switch (command) {
    case 'enable':
    case 'disable':
      // Network events not fully supported, no-op
      return {};

    case 'setCacheDisabled': {
      if (page) {
        await page.setCacheEnabled(!(params.cacheDisabled as boolean));
      }
      return {};
    }

    case 'setExtraHTTPHeaders': {
      const headers = params.headers as Record<string, string>;

      // Store headers in session
      session.extraHTTPHeaders.clear();
      for (const [name, value] of Object.entries(headers)) {
        session.extraHTTPHeaders.set(name, value);
      }

      // Apply to page
      if (page) {
        await page.setExtraHTTPHeaders(headers);
      }

      return {};
    }

    case 'setCookie': {
      if (!page) throw new Error('No page available');

      const cookie = {
        name: params.name as string,
        value: params.value as string,
        url: params.url as string | undefined,
        domain: params.domain as string | undefined,
        path: params.path as string | undefined,
        secure: params.secure as boolean | undefined,
        httpOnly: params.httpOnly as boolean | undefined,
        sameSite: params.sameSite as 'Strict' | 'Lax' | 'None' | undefined,
        expires: params.expires as number | undefined,
      };

      await page.setCookie(cookie);

      return { success: true };
    }

    case 'setCookies': {
      if (!page) throw new Error('No page available');

      const cookies = params.cookies as Array<{
        name: string;
        value: string;
        url?: string;
        domain?: string;
        path?: string;
        secure?: boolean;
        httpOnly?: boolean;
        sameSite?: 'Strict' | 'Lax' | 'None';
        expires?: number;
      }>;

      await page.setCookie(...cookies);

      return {};
    }

    case 'getCookies': {
      if (!page) throw new Error('No page available');

      const urls = params.urls as string[] | undefined;
      const cookies = await page.cookies(...(urls || []));

      return {
        cookies: cookies.map(c => ({
          name: c.name,
          value: c.value,
          domain: c.domain,
          path: c.path,
          expires: c.expires,
          size: c.name.length + c.value.length,
          httpOnly: c.httpOnly,
          secure: c.secure,
          session: c.session,
          sameSite: c.sameSite,
        })),
      };
    }

    case 'deleteCookies': {
      if (!page) throw new Error('No page available');

      const name = params.name as string;
      const url = params.url as string | undefined;
      const domain = params.domain as string | undefined;
      const path = params.path as string | undefined;

      await page.deleteCookie({
        name,
        url,
        domain,
        path,
      });

      return {};
    }

    case 'clearBrowserCookies': {
      if (!page) throw new Error('No page available');

      // Get all cookies and delete them
      const cookies = await page.cookies();
      for (const cookie of cookies) {
        await page.deleteCookie(cookie);
      }

      return {};
    }

    case 'setUserAgentOverride': {
      if (!page) throw new Error('No page available');

      const userAgent = params.userAgent as string;
      await page.setUserAgent(userAgent);

      return {};
    }

    default:
      throw new Error(`Unknown Network method: ${command}`);
  }
}
