import { describe, it, expect } from 'vitest';
import { extractGatewayToken, verifyGatewayToken } from './middleware';
import { createMockEnv } from '../test-utils';
import type { Context } from 'hono';
import type { AppEnv } from '../types';

function createMockContext(options: {
  authHeader?: string;
  queryToken?: string;
  env?: Partial<Parameters<typeof createMockEnv>[0]>;
}): Context<AppEnv> {
  const headers = new Headers();
  if (options.authHeader) {
    headers.set('Authorization', options.authHeader);
  }

  const url = new URL('http://localhost/test');
  if (options.queryToken) {
    url.searchParams.set('token', options.queryToken);
  }

  return {
    req: {
      header: (name: string) => headers.get(name),
      query: (name: string) => url.searchParams.get(name) || undefined,
      raw: { headers },
      url: url.toString(),
    },
    env: createMockEnv(options.env),
  } as unknown as Context<AppEnv>;
}

describe('extractGatewayToken', () => {
  it('extracts token from Authorization Bearer header', () => {
    const c = createMockContext({ authHeader: 'Bearer my-secret-token' });
    expect(extractGatewayToken(c)).toBe('my-secret-token');
  });

  it('handles case-insensitive Bearer prefix', () => {
    const c = createMockContext({ authHeader: 'bearer my-token' });
    expect(extractGatewayToken(c)).toBe('my-token');
  });

  it('extracts token from query parameter', () => {
    const c = createMockContext({ queryToken: 'query-token' });
    expect(extractGatewayToken(c)).toBe('query-token');
  });

  it('prefers Authorization header over query param', () => {
    const c = createMockContext({
      authHeader: 'Bearer header-token',
      queryToken: 'query-token',
    });
    expect(extractGatewayToken(c)).toBe('header-token');
  });

  it('returns null when no token present', () => {
    const c = createMockContext({});
    expect(extractGatewayToken(c)).toBeNull();
  });

  it('returns null for non-Bearer Authorization header', () => {
    const c = createMockContext({ authHeader: 'Basic dXNlcjpwYXNz' });
    expect(extractGatewayToken(c)).toBeNull();
  });

  it('returns null for malformed Bearer header', () => {
    const c = createMockContext({ authHeader: 'Bearer' });
    expect(extractGatewayToken(c)).toBeNull();
  });
});

describe('verifyGatewayToken', () => {
  it('returns true for matching Bearer token', () => {
    const c = createMockContext({
      authHeader: 'Bearer correct-token',
      env: { MOLTBOT_GATEWAY_TOKEN: 'correct-token' },
    });
    expect(verifyGatewayToken(c)).toBe(true);
  });

  it('returns true for matching query param token', () => {
    const c = createMockContext({
      queryToken: 'correct-token',
      env: { MOLTBOT_GATEWAY_TOKEN: 'correct-token' },
    });
    expect(verifyGatewayToken(c)).toBe(true);
  });

  it('returns false for wrong token', () => {
    const c = createMockContext({
      authHeader: 'Bearer wrong-token',
      env: { MOLTBOT_GATEWAY_TOKEN: 'correct-token' },
    });
    expect(verifyGatewayToken(c)).toBe(false);
  });

  it('returns false when no token in request', () => {
    const c = createMockContext({
      env: { MOLTBOT_GATEWAY_TOKEN: 'correct-token' },
    });
    expect(verifyGatewayToken(c)).toBe(false);
  });

  it('returns false when no expected token configured', () => {
    const c = createMockContext({
      authHeader: 'Bearer some-token',
    });
    expect(verifyGatewayToken(c)).toBe(false);
  });
});
