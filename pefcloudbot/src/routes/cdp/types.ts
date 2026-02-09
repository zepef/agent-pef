import type { Browser, Page } from '@cloudflare/puppeteer';

/**
 * CDP Message types
 */
export interface CDPRequest {
  id: number;
  method: string;
  params?: Record<string, unknown>;
}

export interface CDPResponse {
  id: number;
  result?: unknown;
  error?: { code: number; message: string };
}

export interface CDPEvent {
  method: string;
  params?: Record<string, unknown>;
}

/**
 * Session state for a CDP connection
 */
export interface CDPSession {
  browser: Browser;
  pages: Map<string, Page>;  // targetId -> Page
  defaultTargetId: string;
  nodeIdCounter: number;
  nodeMap: Map<number, string>;  // nodeId -> selector path
  objectIdCounter: number;
  objectMap: Map<string, unknown>;  // objectId -> value (for Runtime.getProperties)
  scriptsToEvaluateOnNewDocument: Map<string, string>;  // identifier -> source
  extraHTTPHeaders: Map<string, string>;  // header name -> value
  requestInterceptionEnabled: boolean;
  pendingRequests: Map<string, { request: Request; resolve: (response: Response) => void }>;
}
