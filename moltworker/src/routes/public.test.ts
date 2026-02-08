import { describe, it, expect, vi, beforeEach } from 'vitest';
import { Hono } from 'hono';
import type { AppEnv } from '../types';
import type { Sandbox } from '@cloudflare/sandbox';
import { createMockEnv, createMockSandbox, createMockProcess, suppressConsole } from '../test-utils';

// Mock gateway functions
vi.mock('../gateway', () => ({
  findExistingMoltbotProcess: vi.fn(),
  ensureMoltbotGateway: vi.fn(),
}));

import { findExistingMoltbotProcess, ensureMoltbotGateway } from '../gateway';
import { publicRoutes } from './public';

// Create a test app that mounts publicRoutes like the real app does
function createTestApp(envOverrides: Partial<Parameters<typeof createMockEnv>[0]> = {}) {
  const mockSandbox = createMockSandbox();
  const env = createMockEnv({
    MOLTBOT_GATEWAY_TOKEN: 'test-gateway-token',
    ...envOverrides,
  });

  const app = new Hono<AppEnv>();

  // Simulate the sandbox middleware from index.ts
  app.use('*', async (c, next) => {
    // Hono bindings need to be set on c.env directly for subrouters
    (c as any).env = env;
    c.set('sandbox', mockSandbox.sandbox);
    await next();
  });

  app.route('/', publicRoutes);

  return { app, env, ...mockSandbox };
}

beforeEach(() => {
  vi.clearAllMocks();
  suppressConsole();
});

describe('GET /sandbox-health', () => {
  it('returns ok status with gateway port', async () => {
    const { app } = createTestApp();
    const res = await app.request('/sandbox-health');
    expect(res.status).toBe(200);

    const body = await res.json() as Record<string, any>;
    expect(body).toEqual({
      status: 'ok',
      service: 'moltbot-sandbox',
      gateway_port: 18789,
    });
  });
});

describe('GET /api/status', () => {
  it('returns not_running when no process exists', async () => {
    vi.mocked(findExistingMoltbotProcess).mockResolvedValue(null);
    const { app } = createTestApp();

    const res = await app.request('/api/status');
    expect(res.status).toBe(200);

    const body = await res.json() as Record<string, any>;
    expect(body).toEqual({ ok: false, status: 'not_running' });
  });

  it('returns running when process exists and port responds', async () => {
    const mockProcess = {
      id: 'proc-1',
      status: 'running',
      waitForPort: vi.fn().mockResolvedValue(undefined),
    };
    vi.mocked(findExistingMoltbotProcess).mockResolvedValue(mockProcess as any);
    const { app } = createTestApp();

    const res = await app.request('/api/status');
    expect(res.status).toBe(200);

    const body = await res.json() as Record<string, any>;
    expect(body).toEqual({ ok: true, status: 'running', processId: 'proc-1' });
  });

  it('returns not_responding when process exists but port times out', async () => {
    const mockProcess = {
      id: 'proc-1',
      status: 'running',
      waitForPort: vi.fn().mockRejectedValue(new Error('timeout')),
    };
    vi.mocked(findExistingMoltbotProcess).mockResolvedValue(mockProcess as any);
    const { app } = createTestApp();

    const res = await app.request('/api/status');
    expect(res.status).toBe(200);

    const body = await res.json() as Record<string, any>;
    expect(body).toEqual({ ok: false, status: 'not_responding', processId: 'proc-1' });
  });

  it('returns error status on exception', async () => {
    vi.mocked(findExistingMoltbotProcess).mockRejectedValue(new Error('sandbox error'));
    const { app } = createTestApp();

    const res = await app.request('/api/status');
    expect(res.status).toBe(200);

    const body = await res.json() as Record<string, any>;
    expect(body.ok).toBe(false);
    expect(body.status).toBe('error');
    expect(body.error).toBe('sandbox error');
  });
});

describe('GET /telegram/webhook', () => {
  it('returns ok for GET verification request', async () => {
    const { app } = createTestApp();
    const res = await app.request('/telegram/webhook');
    expect(res.status).toBe(200);

    const body = await res.json() as Record<string, any>;
    expect(body).toEqual({ ok: true, message: 'Telegram webhook endpoint' });
  });
});

describe('POST /telegram/webhook', () => {
  it('proxies webhook to container', async () => {
    const { app, containerFetchMock } = createTestApp();
    containerFetchMock.mockResolvedValue(new Response(JSON.stringify({ ok: true }), { status: 200 }));

    const res = await app.request('/telegram/webhook', {
      method: 'POST',
      body: JSON.stringify({ update_id: 123 }),
      headers: { 'Content-Type': 'application/json' },
    });

    expect(res.status).toBe(200);
  });
});

describe('Gateway token-protected endpoints', () => {
  describe('GET /api/start-debug', () => {
    it('returns 401 without token', async () => {
      const { app } = createTestApp();
      const res = await app.request('/api/start-debug');
      expect(res.status).toBe(401);

      const body = await res.json() as Record<string, any>;
      expect(body.ok).toBe(false);
      expect(body.error).toContain('Invalid or missing token');
    });

    it('returns 401 with wrong token in query', async () => {
      const { app } = createTestApp();
      const res = await app.request('/api/start-debug?token=wrong-token');
      expect(res.status).toBe(401);
    });

    it('authenticates with Authorization header', async () => {
      vi.mocked(ensureMoltbotGateway).mockResolvedValue({
        id: 'proc-1',
        status: 'running',
        getLogs: vi.fn().mockResolvedValue({ stdout: 'started', stderr: '' }),
      } as any);

      const { app } = createTestApp();
      const res = await app.request('/api/start-debug', {
        headers: { 'Authorization': 'Bearer test-gateway-token' },
      });
      expect(res.status).toBe(200);

      const body = await res.json() as Record<string, any>;
      expect(body.ok).toBe(true);
    });

    it('authenticates with query param (backwards compat)', async () => {
      vi.mocked(ensureMoltbotGateway).mockResolvedValue({
        id: 'proc-1',
        status: 'running',
        getLogs: vi.fn().mockResolvedValue({ stdout: 'started', stderr: '' }),
      } as any);

      const { app } = createTestApp();
      const res = await app.request('/api/start-debug?token=test-gateway-token');
      expect(res.status).toBe(200);

      const body = await res.json() as Record<string, any>;
      expect(body.ok).toBe(true);
    });
  });

  describe('POST /api/restart', () => {
    it('returns 401 without token', async () => {
      const { app } = createTestApp();
      const res = await app.request('/api/restart', { method: 'POST' });
      expect(res.status).toBe(401);
    });

    it('kills existing process and returns success', async () => {
      const mockKill = vi.fn().mockResolvedValue(undefined);
      vi.mocked(findExistingMoltbotProcess).mockResolvedValue({
        id: 'proc-1',
        status: 'running',
        kill: mockKill,
      } as any);

      const { app } = createTestApp();
      const res = await app.request('/api/restart', {
        method: 'POST',
        headers: { 'Authorization': 'Bearer test-gateway-token' },
      });
      expect(res.status).toBe(200);

      const body = await res.json() as Record<string, any>;
      expect(body.ok).toBe(true);
      expect(mockKill).toHaveBeenCalled();
    });

    it('handles no existing process', async () => {
      vi.mocked(findExistingMoltbotProcess).mockResolvedValue(null);

      const { app } = createTestApp();
      const res = await app.request('/api/restart', {
        method: 'POST',
        headers: { 'Authorization': 'Bearer test-gateway-token' },
      });
      expect(res.status).toBe(200);

      const body = await res.json() as Record<string, any>;
      expect(body.ok).toBe(true);
      expect(body.message).toContain('will restart');
    });
  });

  describe('POST /api/force-kill', () => {
    it('returns 401 without token', async () => {
      const { app } = createTestApp();
      const res = await app.request('/api/force-kill', { method: 'POST' });
      expect(res.status).toBe(401);
    });

    it('executes kill commands and returns success', async () => {
      vi.useFakeTimers();
      const { app, startProcessMock } = createTestApp();
      startProcessMock.mockResolvedValue(
        createMockProcess('killed', { status: 'completed' })
      );

      const resPromise = app.request('/api/force-kill', {
        method: 'POST',
        headers: { 'Authorization': 'Bearer test-gateway-token' },
      });

      // Advance through all the setTimeout delays in force-kill handler
      await vi.advanceTimersByTimeAsync(10000);

      const res = await resPromise;
      expect(res.status).toBe(200);

      const body = await res.json() as Record<string, any>;
      expect(body.ok).toBe(true);
      expect(body.message).toContain('Force killed');
      vi.useRealTimers();
    });
  });

  describe('GET /api/process-logs/:id', () => {
    it('returns 401 without token', async () => {
      const { app } = createTestApp();
      const res = await app.request('/api/process-logs/some-id');
      expect(res.status).toBe(401);
    });

    it('returns process logs', async () => {
      const { app, listProcessesMock } = createTestApp();
      listProcessesMock.mockResolvedValue([
        {
          id: 'proc-1',
          command: 'start-moltbot.sh',
          status: 'running',
          exitCode: null,
          startTime: new Date('2026-01-01'),
          endTime: null,
          getLogs: vi.fn().mockResolvedValue({ stdout: 'gateway started', stderr: '' }),
        },
      ]);

      const res = await app.request('/api/process-logs/proc-1', {
        headers: { 'Authorization': 'Bearer test-gateway-token' },
      });
      expect(res.status).toBe(200);

      const body = await res.json() as Record<string, any>;
      expect(body.ok).toBe(true);
      expect(body.processId).toBe('proc-1');
      expect(body.stdout).toBe('gateway started');
    });

    it('returns error for non-existent process', async () => {
      const { app, listProcessesMock } = createTestApp();
      listProcessesMock.mockResolvedValue([]);

      const res = await app.request('/api/process-logs/unknown', {
        headers: { 'Authorization': 'Bearer test-gateway-token' },
      });
      expect(res.status).toBe(200);

      const body = await res.json() as Record<string, any>;
      expect(body.ok).toBe(false);
      expect(body.error).toBe('Process not found');
    });
  });
});

describe('GET /api/telegram-status', () => {
  it('returns telegram configuration status', async () => {
    const { app, startProcessMock } = createTestApp({
      TELEGRAM_BOT_TOKEN: 'bot123:token',
    });

    vi.mocked(findExistingMoltbotProcess).mockResolvedValue(null);

    // Mock the cat process for reading clawdbot.json
    startProcessMock.mockResolvedValue(
      createMockProcess(JSON.stringify({
        channels: {
          telegram: { botToken: '12345678:secret-token-value' },
        },
      }), { status: 'completed' })
    );

    const res = await app.request('/api/telegram-status');
    expect(res.status).toBe(200);

    const body = await res.json() as Record<string, any>;
    expect(body.hasTelegramTokenEnv).toBe(true);
    // Token should be redacted
    if (body.containerConfig?.botToken) {
      expect(body.containerConfig.botToken).toContain('...');
      expect(body.containerConfig.botToken.length).toBeLessThan(20);
    }
  });
});
