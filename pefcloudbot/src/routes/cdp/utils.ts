import type { CDPResponse, CDPEvent } from './types';

/**
 * Send a CDP response
 */
export function sendResponse(ws: WebSocket, id: number, result: unknown): void {
  const response: CDPResponse = { id, result };
  ws.send(JSON.stringify(response));
}

/**
 * Send a CDP error
 */
export function sendError(ws: WebSocket, id: number, code: number, message: string): void {
  const response: CDPResponse = { id, error: { code, message } };
  ws.send(JSON.stringify(response));
}

/**
 * Send a CDP event
 */
export function sendEvent(ws: WebSocket, method: string, params?: Record<string, unknown>): void {
  const event: CDPEvent = { method, params };
  ws.send(JSON.stringify(event));
}

/**
 * Constant-time string comparison to prevent timing attacks
 */
export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) {
    return false;
  }

  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

/**
 * Extract CDP secret from Authorization header or query parameter.
 * WebSocket clients often can't set custom headers, so query param
 * remains supported for the CDP endpoint.
 */
export function extractCDPSecret(c: { req: { header: (name: string) => string | undefined; url: string } }): string | null {
  // Prefer Authorization header
  const authHeader = c.req.header('Authorization');
  if (authHeader) {
    const match = authHeader.match(/^Bearer\s+(.+)$/i);
    if (match) {
      return match[1];
    }
  }

  // Fall back to query parameter (needed for WebSocket clients)
  const url = new URL(c.req.url);
  return url.searchParams.get('secret');
}
