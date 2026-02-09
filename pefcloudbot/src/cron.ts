/**
 * Scheduled (cron) handler for periodic tasks.
 *
 * Syncs moltbot config/state from the sandbox container to R2 for persistence.
 * Runs on the schedule defined in wrangler.jsonc (default: every 5 minutes).
 */
import { getSandbox } from '@cloudflare/sandbox';
import type { MoltbotEnv } from './types';
import { syncToR2 } from './gateway';
import { buildSandboxOptions } from './sandbox-options';

/**
 * Scheduled handler for cron triggers.
 * Syncs moltbot config/state from container to R2 for persistence.
 */
export async function scheduled(
  _event: ScheduledEvent,
  env: MoltbotEnv,
  _ctx: ExecutionContext,
): Promise<void> {
  const options = buildSandboxOptions(env);
  const sandbox = getSandbox(env.Sandbox, 'moltbot', options);

  console.log('[cron] Starting backup sync to R2...');
  const result = await syncToR2(sandbox, env);

  if (result.success) {
    console.log('[cron] Backup sync completed successfully at', result.lastSync);
  } else {
    console.error('[cron] Backup sync failed:', result.error, result.details || '');
  }
}
