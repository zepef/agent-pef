import { describe, it, expect } from 'vitest';
import { transformErrorMessage } from './websocket-proxy';

describe('transformErrorMessage', () => {
  const host = 'moltbot.example.com';

  it('transforms gateway token missing errors', () => {
    const result = transformErrorMessage('gateway token missing', host);
    expect(result).toContain('Invalid or missing token');
    expect(result).toContain(host);
  });

  it('transforms gateway token mismatch errors', () => {
    const result = transformErrorMessage('gateway token mismatch', host);
    expect(result).toContain('Invalid or missing token');
    expect(result).toContain(host);
  });

  it('transforms pairing required errors', () => {
    const result = transformErrorMessage('pairing required', host);
    expect(result).toContain('Pairing required');
    expect(result).toContain('/_admin/');
  });

  it('passes through unknown messages unchanged', () => {
    const msg = 'something else happened';
    const result = transformErrorMessage(msg, host);
    expect(result).toBe(msg);
  });

  it('passes through empty messages unchanged', () => {
    const result = transformErrorMessage('', host);
    expect(result).toBe('');
  });
});
