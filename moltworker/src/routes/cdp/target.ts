import type { CDPSession } from './types';
import { sendEvent } from './utils';

/**
 * Target domain handlers
 */
export async function handleTarget(
  session: CDPSession,
  command: string,
  params: Record<string, unknown>,
  ws: WebSocket
): Promise<unknown> {
  switch (command) {
    case 'createTarget': {
      const url = (params.url as string) || 'about:blank';
      const page = await session.browser.newPage();
      const targetId = crypto.randomUUID();

      session.pages.set(targetId, page);

      if (url !== 'about:blank') {
        await page.goto(url);
      }

      sendEvent(ws, 'Target.targetCreated', {
        targetInfo: {
          targetId,
          type: 'page',
          title: await page.title(),
          url: page.url(),
          attached: true,
        },
      });

      return { targetId };
    }

    case 'closeTarget': {
      const targetId = params.targetId as string;
      const page = session.pages.get(targetId);

      if (!page) {
        throw new Error(`Target not found: ${targetId}`);
      }

      await page.close();
      session.pages.delete(targetId);

      sendEvent(ws, 'Target.targetDestroyed', { targetId });

      return { success: true };
    }

    case 'getTargets': {
      const targets = [];
      for (const [targetId, page] of session.pages) {
        targets.push({
          targetId,
          type: 'page',
          title: await page.title(),
          url: page.url(),
          attached: true,
        });
      }
      return { targetInfos: targets };
    }

    case 'attachToTarget':
      // Already attached
      return { sessionId: params.targetId };

    default:
      throw new Error(`Unknown Target method: ${command}`);
  }
}
