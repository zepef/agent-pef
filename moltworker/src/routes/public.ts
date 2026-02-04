import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { MOLTBOT_PORT } from '../config';
import { findExistingMoltbotProcess, ensureMoltbotGateway } from '../gateway';

/**
 * Public routes - NO Cloudflare Access authentication required
 * 
 * These routes are mounted BEFORE the auth middleware is applied.
 * Includes: health checks, static assets, and public API endpoints.
 */
const publicRoutes = new Hono<AppEnv>();

// GET /sandbox-health - Health check endpoint
publicRoutes.get('/sandbox-health', (c) => {
  return c.json({
    status: 'ok',
    service: 'moltbot-sandbox',
    gateway_port: MOLTBOT_PORT,
  });
});

// GET /logo.png - Serve logo from ASSETS binding
publicRoutes.get('/logo.png', (c) => {
  return c.env.ASSETS.fetch(c.req.raw);
});

// GET /logo-small.png - Serve small logo from ASSETS binding
publicRoutes.get('/logo-small.png', (c) => {
  return c.env.ASSETS.fetch(c.req.raw);
});

// GET /api/status - Public health check for gateway status (no auth required)
publicRoutes.get('/api/status', async (c) => {
  const sandbox = c.get('sandbox');
  
  try {
    const process = await findExistingMoltbotProcess(sandbox);
    if (!process) {
      return c.json({ ok: false, status: 'not_running' });
    }
    
    // Process exists, check if it's actually responding
    // Try to reach the gateway with a short timeout
    try {
      await process.waitForPort(18789, { mode: 'tcp', timeout: 5000 });
      return c.json({ ok: true, status: 'running', processId: process.id });
    } catch {
      return c.json({ ok: false, status: 'not_responding', processId: process.id });
    }
  } catch (err) {
    return c.json({ ok: false, status: 'error', error: err instanceof Error ? err.message : 'Unknown error' });
  }
});

// GET /_admin/assets/* - Admin UI static assets (CSS, JS need to load for login redirect)
// Assets are built to dist/client with base "/_admin/"
publicRoutes.get('/_admin/assets/*', async (c) => {
  const url = new URL(c.req.url);
  // Rewrite /_admin/assets/* to /assets/* for the ASSETS binding
  const assetPath = url.pathname.replace('/_admin/assets/', '/assets/');
  const assetUrl = new URL(assetPath, url.origin);
  return c.env.ASSETS.fetch(new Request(assetUrl.toString(), c.req.raw));
});

// POST /telegram/webhook - Telegram webhook endpoint (no auth required)
// This proxies Telegram webhook updates to the moltbot gateway
publicRoutes.post('/telegram/webhook', async (c) => {
  const sandbox = c.get('sandbox');

  try {
    // Forward the webhook to the container
    const response = await sandbox.containerFetch(c.req.raw, MOLTBOT_PORT);
    return response;
  } catch (err) {
    console.error('[TELEGRAM] Webhook proxy error:', err);
    return c.json({ ok: false, error: 'Gateway not available' }, 503);
  }
});

// GET /telegram/webhook - Telegram webhook verification (no auth required)
publicRoutes.get('/telegram/webhook', async (c) => {
  return c.json({ ok: true, message: 'Telegram webhook endpoint' });
});

// GET /api/start-debug - Public endpoint to explicitly start gateway and report errors
// Requires the gateway token as a query parameter for basic protection
publicRoutes.get('/api/start-debug', async (c) => {
  const sandbox = c.get('sandbox');
  const token = c.req.query('token');

  // Require token for this debug endpoint
  if (!token || token !== c.env.MOLTBOT_GATEWAY_TOKEN) {
    return c.json({ ok: false, error: 'Invalid token' }, 401);
  }

  try {
    console.log('[start-debug] Starting gateway...');
    const process = await ensureMoltbotGateway(sandbox, c.env);
    console.log('[start-debug] Gateway started, process:', process.id);

    const logs = await process.getLogs();
    return c.json({
      ok: true,
      processId: process.id,
      status: process.status,
      stdout: logs.stdout?.slice(-3000) || '',
      stderr: logs.stderr?.slice(-1000) || '',
    });
  } catch (err) {
    console.error('[start-debug] Failed to start gateway:', err);

    // Try to get logs from failed processes
    let failedProcessLogs: { processId: string; stdout: string; stderr: string }[] = [];
    try {
      const allProcesses = await sandbox.listProcesses();
      const failedProcs = allProcesses.filter(p =>
        p.command?.includes('start-moltbot.sh') && p.status === 'failed'
      ).slice(0, 3);

      for (const proc of failedProcs) {
        const logs = await proc.getLogs();
        failedProcessLogs.push({
          processId: proc.id,
          stdout: logs.stdout?.slice(-2000) || '',
          stderr: logs.stderr?.slice(-2000) || '',
        });
      }
    } catch (e) {
      console.error('[start-debug] Failed to get failed process logs:', e);
    }

    return c.json({
      ok: false,
      error: err instanceof Error ? err.message : 'Unknown error',
      stack: err instanceof Error ? err.stack : undefined,
      failedProcessLogs,
    });
  }
});

// POST /api/restart - Public endpoint to restart the gateway (for debugging)
// Requires the gateway token as a query parameter for basic protection
publicRoutes.post('/api/restart', async (c) => {
  const sandbox = c.get('sandbox');
  const token = c.req.query('token');

  // Require token for restart
  if (!token || token !== c.env.MOLTBOT_GATEWAY_TOKEN) {
    return c.json({ ok: false, error: 'Invalid token' }, 401);
  }

  try {
    const process = await findExistingMoltbotProcess(sandbox);
    if (process) {
      await process.kill();
    }
    return c.json({ ok: true, message: 'Gateway process killed, will restart on next request' });
  } catch (err) {
    return c.json({ ok: false, error: err instanceof Error ? err.message : 'Unknown error' });
  }
});

// POST /api/force-kill - Force kill all gateway processes (for stuck processes)
publicRoutes.post('/api/force-kill', async (c) => {
  const sandbox = c.get('sandbox');
  const token = c.req.query('token');

  if (!token || token !== c.env.MOLTBOT_GATEWAY_TOKEN) {
    return c.json({ ok: false, error: 'Invalid token' }, 401);
  }

  try {
    // Kill any process using port 18789
    const fuserProc = await sandbox.startProcess('fuser -k 18789/tcp 2>/dev/null || true');
    await new Promise(r => setTimeout(r, 2000));

    // Kill any clawdbot/node gateway processes
    const killProc = await sandbox.startProcess('pkill -9 -f clawdbot || pkill -9 -f "node.*18789" || true');
    await new Promise(r => setTimeout(r, 2000));
    const killLogs = await killProc.getLogs();

    // Also remove lock files
    const cleanProc = await sandbox.startProcess('rm -f /tmp/clawdbot-gateway.lock /root/.clawdbot/gateway.lock /tmp/clawdbot/*.lock 2>/dev/null || true');
    await new Promise(r => setTimeout(r, 1000));

    return c.json({
      ok: true,
      message: 'Force killed all gateway processes',
      killOutput: killLogs.stdout || '',
      killError: killLogs.stderr || ''
    });
  } catch (err) {
    return c.json({ ok: false, error: err instanceof Error ? err.message : 'Unknown error' });
  }
});

// GET /api/process-logs/:id - Get logs from a specific process
publicRoutes.get('/api/process-logs/:id', async (c) => {
  const sandbox = c.get('sandbox');
  const processId = c.req.param('id');
  const token = c.req.query('token');

  if (!token || token !== c.env.MOLTBOT_GATEWAY_TOKEN) {
    return c.json({ ok: false, error: 'Invalid token' }, 401);
  }

  try {
    const processes = await sandbox.listProcesses();
    const proc = processes.find(p => p.id === processId);

    if (!proc) {
      return c.json({ ok: false, error: 'Process not found' });
    }

    const logs = await proc.getLogs();
    return c.json({
      ok: true,
      processId: proc.id,
      command: proc.command,
      status: proc.status,
      exitCode: proc.exitCode,
      startTime: proc.startTime?.toISOString(),
      endTime: proc.endTime?.toISOString(),
      stdout: logs.stdout || '',
      stderr: logs.stderr || '',
    });
  } catch (err) {
    return c.json({ ok: false, error: err instanceof Error ? err.message : 'Unknown error' });
  }
});

// GET /api/telegram-status - Public endpoint to check Telegram config (for debugging)
publicRoutes.get('/api/telegram-status', async (c) => {
  const sandbox = c.get('sandbox');

  try {
    // Check if TELEGRAM_BOT_TOKEN env var is set
    const hasTelegramToken = !!c.env.TELEGRAM_BOT_TOKEN;

    // Read the container's clawdbot.json to check Telegram config
    const proc = await sandbox.startProcess('cat /root/.clawdbot/clawdbot.json');

    let attempts = 0;
    while (attempts < 10) {
      await new Promise(r => setTimeout(r, 200));
      if (proc.status !== 'running') break;
      attempts++;
    }

    const logs = await proc.getLogs();
    const stdout = logs.stdout || '';

    let telegramConfig = null;
    try {
      const config = JSON.parse(stdout);
      telegramConfig = config.channels?.telegram || null;
      // Redact the bot token for security
      if (telegramConfig?.botToken) {
        telegramConfig.botToken = telegramConfig.botToken.slice(0, 10) + '...';
      }
    } catch {
      // Not valid JSON
    }

    // Get all processes for debugging
    const allProcesses = await sandbox.listProcesses();
    const processInfo = allProcesses.map(p => ({
      id: p.id,
      command: p.command?.slice(0, 50),
      status: p.status,
    }));

    // Get startup logs to check if Telegram provider started
    const process = await findExistingMoltbotProcess(sandbox);
    let startupLogs = '';
    if (process) {
      const processLogs = await process.getLogs();
      startupLogs = processLogs.stdout || '';
    }

    const telegramStarted = startupLogs.includes('[telegram]');

    return c.json({
      hasTelegramTokenEnv: hasTelegramToken,
      containerConfig: telegramConfig,
      telegramProviderStarted: telegramStarted,
      logsPreview: startupLogs.slice(0, 2000),
      processes: processInfo,
    });
  } catch (err) {
    return c.json({
      error: err instanceof Error ? err.message : 'Unknown error',
      hasTelegramTokenEnv: !!c.env.TELEGRAM_BOT_TOKEN,
    });
  }
});

export { publicRoutes };
