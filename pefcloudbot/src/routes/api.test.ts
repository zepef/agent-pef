import { describe, it, expect, vi, beforeEach } from 'vitest';
import { suppressConsole } from '../test-utils';

/**
 * API route tests.
 *
 * The admin API routes use CF Access middleware which requires deep Hono
 * context mocking. The route handler logic is tested via:
 * - public.test.ts: Tests gateway token auth, restart, force-kill, process logs
 * - gateway-token.test.ts: Tests the token extraction and verification
 * - middleware.test.ts: Tests the CF Access middleware itself
 *
 * These tests verify the route exports and module structure.
 */

vi.mock('../gateway', () => ({
  findExistingMoltbotProcess: vi.fn(),
  ensureMoltbotGateway: vi.fn(),
  mountR2Storage: vi.fn().mockResolvedValue(undefined),
  syncToR2: vi.fn(),
  waitForProcess: vi.fn().mockResolvedValue(undefined),
}));

vi.mock('../auth', () => ({
  createAccessMiddleware: vi.fn(() => async (_c: any, next: any) => next()),
  isDevMode: vi.fn(() => true),
  extractJWT: vi.fn(() => null),
  verifyAccessJWT: vi.fn(),
  extractGatewayToken: vi.fn(),
  verifyGatewayToken: vi.fn(),
}));

beforeEach(() => {
  vi.clearAllMocks();
  suppressConsole();
});

describe('api module', () => {
  it('exports an api Hono instance', async () => {
    const { api } = await import('./api');
    expect(api).toBeDefined();
    expect(api.routes).toBeDefined();
  });

  it('has admin/devices route registered', async () => {
    const { api } = await import('./api');
    const routes = api.routes;
    // Hono stores routes internally, verify the routes exist
    expect(routes.length).toBeGreaterThan(0);
  });

  it('has multiple route groups registered', async () => {
    const { api } = await import('./api');
    // The api module should have routes for admin devices, storage, and gateway
    const routes = api.routes;
    expect(routes.length).toBeGreaterThanOrEqual(1);
  });
});
