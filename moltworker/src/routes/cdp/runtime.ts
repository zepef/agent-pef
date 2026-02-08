import type { Page } from '@cloudflare/puppeteer';
import type { CDPSession } from './types';

/**
 * Runtime domain handlers
 */
export async function handleRuntime(
  session: CDPSession,
  page: Page,
  command: string,
  params: Record<string, unknown>
): Promise<unknown> {
  switch (command) {
    case 'evaluate': {
      const expression = params.expression as string;
      if (!expression) throw new Error('expression is required');

      const returnByValue = params.returnByValue ?? true;
      const awaitPromise = params.awaitPromise ?? false;

      try {
        // Wrap in async IIFE if awaitPromise is true
        const wrappedExpression = awaitPromise
          ? `(async () => { return ${expression}; })()`
          : expression;

        const result = await page.evaluate(wrappedExpression);

        // Store object reference if not returning by value
        let objectId: string | undefined;
        if (!returnByValue && result !== null && typeof result === 'object') {
          objectId = `obj-${session.objectIdCounter++}`;
          session.objectMap.set(objectId, result);
        }

        return {
          result: {
            type: typeof result,
            subtype: Array.isArray(result) ? 'array' : (result === null ? 'null' : undefined),
            className: result?.constructor?.name,
            value: returnByValue ? result : undefined,
            objectId,
            description: String(result),
          },
        };
      } catch (err) {
        return {
          exceptionDetails: {
            exceptionId: 1,
            text: err instanceof Error ? err.message : 'Evaluation failed',
            lineNumber: 0,
            columnNumber: 0,
          },
        };
      }
    }

    case 'callFunctionOn': {
      const functionDeclaration = params.functionDeclaration as string;
      const args = (params.arguments as Array<{ value?: unknown; objectId?: string }>) || [];
      const returnByValue = params.returnByValue ?? true;

      try {
        // Resolve object references in arguments
        const argValues = args.map(a => {
          if (a.objectId) {
            return session.objectMap.get(a.objectId);
          }
          return a.value;
        });

        const fn = new Function(`return (${functionDeclaration}).apply(this, arguments)`);
        const result = await page.evaluate(fn as () => unknown, ...argValues);

        let objectId: string | undefined;
        if (!returnByValue && result !== null && typeof result === 'object') {
          objectId = `obj-${session.objectIdCounter++}`;
          session.objectMap.set(objectId, result);
        }

        return {
          result: {
            type: typeof result,
            subtype: Array.isArray(result) ? 'array' : (result === null ? 'null' : undefined),
            value: returnByValue ? result : undefined,
            objectId,
          },
        };
      } catch (err) {
        return {
          exceptionDetails: {
            exceptionId: 1,
            text: err instanceof Error ? err.message : 'Call failed',
            lineNumber: 0,
            columnNumber: 0,
          },
        };
      }
    }

    case 'getProperties': {
      const objectId = params.objectId as string;
      const ownProperties = params.ownProperties ?? true;

      const obj = session.objectMap.get(objectId);
      if (!obj || typeof obj !== 'object') {
        return { result: [] };
      }

      const properties: Array<{
        name: string;
        value: { type: string; value?: unknown; description?: string };
        writable?: boolean;
        configurable?: boolean;
        enumerable?: boolean;
        isOwn?: boolean;
      }> = [];

      const keys = ownProperties ? Object.getOwnPropertyNames(obj) : Object.keys(obj as object);

      for (const key of keys) {
        const value = (obj as Record<string, unknown>)[key];
        const descriptor = Object.getOwnPropertyDescriptor(obj, key);

        properties.push({
          name: key,
          value: {
            type: typeof value,
            value: value,
            description: String(value),
          },
          writable: descriptor?.writable,
          configurable: descriptor?.configurable,
          enumerable: descriptor?.enumerable,
          isOwn: true,
        });
      }

      return { result: properties };
    }

    case 'releaseObject': {
      const objectId = params.objectId as string;
      session.objectMap.delete(objectId);
      return {};
    }

    case 'releaseObjectGroup': {
      // Release all objects (simplified - we don't track groups)
      session.objectMap.clear();
      return {};
    }

    case 'enable':
    case 'disable':
      return {};

    default:
      throw new Error(`Unknown Runtime method: ${command}`);
  }
}
