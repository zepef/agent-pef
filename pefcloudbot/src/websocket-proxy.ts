/**
 * WebSocket proxy with error message transformation.
 *
 * Relays WebSocket messages between the client and the Moltbot gateway
 * running inside the sandbox container. Error messages from the gateway
 * are intercepted and rewritten to be more user-friendly.
 */
import type { Sandbox } from '@cloudflare/sandbox';
import { MOLTBOT_PORT } from './config';

/**
 * Transform error messages from the gateway to be more user-friendly.
 */
export function transformErrorMessage(message: string, host: string): string {
  if (message.includes('gateway token missing') || message.includes('gateway token mismatch')) {
    return `Invalid or missing token. Visit https://${host}?token={REPLACE_WITH_YOUR_TOKEN}`;
  }

  if (message.includes('pairing required')) {
    return `Pairing required. Visit https://${host}/_admin/`;
  }

  return message;
}

/**
 * Create an intercepting WebSocket proxy response.
 *
 * Sets up a relay between the client and the container WebSocket,
 * transforming error messages in transit.
 */
export async function createWebSocketProxy(
  request: Request,
  sandbox: Sandbox,
  host: string,
): Promise<Response> {
  console.log('[WS] Proxying WebSocket connection to Moltbot');
  console.log('[WS] URL:', request.url);

  // Get WebSocket connection to the container
  const containerResponse = await sandbox.wsConnect(request, MOLTBOT_PORT);
  console.log('[WS] wsConnect response status:', containerResponse.status);

  // Get the container-side WebSocket
  const containerWs = containerResponse.webSocket;
  if (!containerWs) {
    console.error('[WS] No WebSocket in container response - falling back to direct proxy');
    return containerResponse;
  }

  console.log('[WS] Got container WebSocket, setting up interception');

  // Create a WebSocket pair for the client
  const [clientWs, serverWs] = Object.values(new WebSocketPair());

  // Accept both WebSockets
  serverWs.accept();
  containerWs.accept();

  // Relay messages from client to container
  serverWs.addEventListener('message', (event) => {
    console.log('[WS] Client -> Container:', typeof event.data, typeof event.data === 'string' ? event.data.slice(0, 200) : '(binary)');
    if (containerWs.readyState === WebSocket.OPEN) {
      containerWs.send(event.data);
    } else {
      console.log('[WS] Container not open, readyState:', containerWs.readyState);
    }
  });

  // Relay messages from container to client, with error transformation
  containerWs.addEventListener('message', (event) => {
    console.log('[WS] Container -> Client (raw):', typeof event.data, typeof event.data === 'string' ? event.data.slice(0, 500) : '(binary)');
    let data = event.data;

    // Try to intercept and transform error messages
    if (typeof data === 'string') {
      try {
        const parsed = JSON.parse(data);
        if (parsed.error?.message) {
          parsed.error.message = transformErrorMessage(parsed.error.message, host);
          data = JSON.stringify(parsed);
        }
      } catch {
        // Not JSON, pass through
      }
    }

    if (serverWs.readyState === WebSocket.OPEN) {
      serverWs.send(data);
    } else {
      console.log('[WS] Server not open, readyState:', serverWs.readyState);
    }
  });

  // Handle close events
  serverWs.addEventListener('close', (event) => {
    console.log('[WS] Client closed:', event.code, event.reason);
    containerWs.close(event.code, event.reason);
  });

  containerWs.addEventListener('close', (event) => {
    console.log('[WS] Container closed:', event.code, event.reason);
    // Transform the close reason (truncate to 123 bytes max for WebSocket spec)
    let reason = transformErrorMessage(event.reason, host);
    if (reason.length > 123) {
      reason = reason.slice(0, 120) + '...';
    }
    serverWs.close(event.code, reason);
  });

  // Handle errors
  serverWs.addEventListener('error', (event) => {
    console.error('[WS] Client error:', event);
    containerWs.close(1011, 'Client error');
  });

  containerWs.addEventListener('error', (event) => {
    console.error('[WS] Container error:', event);
    serverWs.close(1011, 'Container error');
  });

  console.log('[WS] Returning intercepted WebSocket response');
  return new Response(null, {
    status: 101,
    webSocket: clientWs,
  });
}
