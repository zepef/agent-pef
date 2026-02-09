import type { Context, Next } from 'hono';
import type { AppEnv, MoltbotEnv } from '../types';
import { verifyAccessJWT } from './jwt';

/**
 * Extract gateway token from Authorization header or query parameter.
 * Prefers the Authorization header (Bearer token) for security.
 * Query parameter support is maintained for backwards compatibility but
 * should be considered deprecated - tokens in URLs appear in server logs,
 * browser history, and referrer headers.
 */
export function extractGatewayToken(c: Context<AppEnv>): string | null {
  // Prefer Authorization header
  const authHeader = c.req.header('Authorization');
  if (authHeader) {
    const match = authHeader.match(/^Bearer\s+(.+)$/i);
    if (match) {
      return match[1];
    }
  }

  // Fall back to query parameter (deprecated)
  return c.req.query('token') || null;
}

/**
 * Verify the gateway token from the request.
 * Returns true if the token matches the expected MOLTBOT_GATEWAY_TOKEN.
 */
export function verifyGatewayToken(c: Context<AppEnv>): boolean {
  const expectedToken = c.env.MOLTBOT_GATEWAY_TOKEN;
  if (!expectedToken) return false;

  const providedToken = extractGatewayToken(c);
  if (!providedToken) return false;

  return providedToken === expectedToken;
}

/**
 * Options for creating an access middleware
 */
export interface AccessMiddlewareOptions {
  /** Response type: 'json' for API routes, 'html' for UI routes */
  type: 'json' | 'html';
  /** Whether to redirect to login when JWT is missing (only for 'html' type) */
  redirectOnMissing?: boolean;
}

/**
 * Check if running in development mode (skips CF Access auth)
 */
export function isDevMode(env: MoltbotEnv): boolean {
  return env.DEV_MODE === 'true';
}

/**
 * Extract JWT from request headers or cookies
 */
export function extractJWT(c: Context<AppEnv>): string | null {
  const jwtHeader = c.req.header('CF-Access-JWT-Assertion');
  const jwtCookie = c.req.raw.headers.get('Cookie')
    ?.split(';')
    .find(cookie => cookie.trim().startsWith('CF_Authorization='))
    ?.split('=')[1];

  return jwtHeader || jwtCookie || null;
}

/**
 * Create a Cloudflare Access authentication middleware
 * 
 * @param options - Middleware options
 * @returns Hono middleware function
 */
export function createAccessMiddleware(options: AccessMiddlewareOptions) {
  const { type, redirectOnMissing = false } = options;

  return async (c: Context<AppEnv>, next: Next) => {
    // Skip auth in dev mode
    if (isDevMode(c.env)) {
      console.warn('[AUTH] DEV_MODE active - skipping all authentication');
      c.set('accessUser', { email: 'dev@localhost', name: 'Dev User' });
      return next();
    }

    const teamDomain = c.env.CF_ACCESS_TEAM_DOMAIN;
    const expectedAud = c.env.CF_ACCESS_AUD;

    // Check if CF Access is configured
    if (!teamDomain || !expectedAud) {
      if (type === 'json') {
        return c.json({
          error: 'Cloudflare Access not configured',
          hint: 'Set CF_ACCESS_TEAM_DOMAIN and CF_ACCESS_AUD environment variables',
        }, 500);
      } else {
        return c.html(`
          <html>
            <body>
              <h1>Admin UI Not Configured</h1>
              <p>Set CF_ACCESS_TEAM_DOMAIN and CF_ACCESS_AUD environment variables.</p>
            </body>
          </html>
        `, 500);
      }
    }

    // Get JWT
    const jwt = extractJWT(c);

    if (!jwt) {
      if (type === 'html' && redirectOnMissing) {
        return c.redirect(`https://${teamDomain}`, 302);
      }
      
      if (type === 'json') {
        return c.json({
          error: 'Unauthorized',
          hint: 'Missing Cloudflare Access JWT. Ensure this route is protected by Cloudflare Access.',
        }, 401);
      } else {
        return c.html(`
          <html>
            <body>
              <h1>Unauthorized</h1>
              <p>Missing Cloudflare Access token.</p>
              <a href="https://${teamDomain}">Login</a>
            </body>
          </html>
        `, 401);
      }
    }

    // Verify JWT
    try {
      const payload = await verifyAccessJWT(jwt, teamDomain, expectedAud);
      c.set('accessUser', { email: payload.email, name: payload.name });
      await next();
    } catch (err) {
      console.error('Access JWT verification failed:', err);
      
      if (type === 'json') {
        return c.json({
          error: 'Unauthorized',
          details: err instanceof Error ? err.message : 'JWT verification failed',
        }, 401);
      } else {
        return c.html(`
          <html>
            <body>
              <h1>Unauthorized</h1>
              <p>Your Cloudflare Access session is invalid or expired.</p>
              <a href="https://${teamDomain}">Login again</a>
            </body>
          </html>
        `, 401);
      }
    }
  };
}
