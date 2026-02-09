import type { Page } from '@cloudflare/puppeteer';
import type { CDPSession } from './types';

/**
 * DOM domain handlers
 */
export async function handleDOM(
  session: CDPSession,
  page: Page,
  command: string,
  params: Record<string, unknown>
): Promise<unknown> {
  switch (command) {
    case 'getDocument': {
      const depth = (params.depth as number) ?? 1;

      // Get basic document structure
      const doc = await page.evaluate((maxDepth: number) => {
        function serializeNode(node: Node, currentDepth: number): unknown {
          const base: Record<string, unknown> = {
            nodeId: Math.floor(Math.random() * 1000000),
            nodeType: node.nodeType,
            nodeName: node.nodeName,
            localName: node.nodeName.toLowerCase(),
            nodeValue: node.nodeValue || '',
          };

          if (node instanceof Element) {
            base.attributes = [];
            for (const attr of node.attributes) {
              (base.attributes as string[]).push(attr.name, attr.value);
            }

            if (currentDepth < maxDepth && node.children.length > 0) {
              base.children = [];
              for (const child of node.children) {
                (base.children as unknown[]).push(serializeNode(child, currentDepth + 1));
              }
              base.childNodeCount = node.children.length;
            } else {
              base.childNodeCount = node.children.length;
            }
          }

          return base;
        }

        return serializeNode(document.documentElement, 0);
      }, depth);

      // Create a stable root nodeId
      const rootNodeId = session.nodeIdCounter++;
      session.nodeMap.set(rootNodeId, 'html');

      return {
        root: {
          nodeId: rootNodeId,
          backendNodeId: rootNodeId,
          nodeType: 9, // Document
          nodeName: '#document',
          localName: '',
          nodeValue: '',
          childNodeCount: 1,
          children: [doc],
          documentURL: page.url(),
          baseURL: page.url(),
        },
      };
    }

    case 'querySelector': {
      const selector = params.selector as string;
      if (!selector) throw new Error('selector is required');

      const element = await page.$(selector);
      if (!element) {
        return { nodeId: 0 };
      }

      const nodeId = session.nodeIdCounter++;
      session.nodeMap.set(nodeId, selector);

      return { nodeId };
    }

    case 'querySelectorAll': {
      const selector = params.selector as string;
      if (!selector) throw new Error('selector is required');

      const elements = await page.$$(selector);
      const nodeIds = elements.map((_, i) => {
        const nodeId = session.nodeIdCounter++;
        session.nodeMap.set(nodeId, `${selector}:nth-of-type(${i + 1})`);
        return nodeId;
      });

      return { nodeIds };
    }

    case 'getOuterHTML': {
      const nodeId = params.nodeId as number;
      const selector = session.nodeMap.get(nodeId);

      if (!selector) {
        // Try to get document HTML
        const html = await page.content();
        return { outerHTML: html };
      }

      const html = await page.evaluate((sel: string) => {
        const el = document.querySelector(sel);
        return el ? el.outerHTML : '';
      }, selector);

      return { outerHTML: html };
    }

    case 'getAttributes': {
      const nodeId = params.nodeId as number;
      const selector = session.nodeMap.get(nodeId);

      if (!selector) throw new Error(`Node not found: ${nodeId}`);

      const attributes = await page.evaluate((sel: string) => {
        const el = document.querySelector(sel);
        if (!el) return [];
        const attrs: string[] = [];
        for (const attr of el.attributes) {
          attrs.push(attr.name, attr.value);
        }
        return attrs;
      }, selector);

      return { attributes };
    }

    case 'setAttributeValue': {
      const nodeId = params.nodeId as number;
      const name = params.name as string;
      const value = params.value as string;
      const selector = session.nodeMap.get(nodeId);

      if (!selector) throw new Error(`Node not found: ${nodeId}`);

      await page.evaluate((sel: string, attrName: string, attrValue: string) => {
        const el = document.querySelector(sel);
        if (el) el.setAttribute(attrName, attrValue);
      }, selector, name, value);

      return {};
    }

    case 'focus': {
      const nodeId = params.nodeId as number;
      const selector = session.nodeMap.get(nodeId);

      if (!selector) throw new Error(`Node not found: ${nodeId}`);

      await page.focus(selector);
      return {};
    }

    case 'getBoxModel': {
      const nodeId = params.nodeId as number;
      const selector = session.nodeMap.get(nodeId);

      if (!selector) throw new Error(`Node not found: ${nodeId}`);

      const boxModel = await page.evaluate((sel: string) => {
        const el = document.querySelector(sel);
        if (!el) return null;

        const rect = el.getBoundingClientRect();
        const scrollX = window.scrollX;
        const scrollY = window.scrollY;

        // Content box (innermost)
        const style = window.getComputedStyle(el);
        const paddingTop = parseFloat(style.paddingTop);
        const paddingRight = parseFloat(style.paddingRight);
        const paddingBottom = parseFloat(style.paddingBottom);
        const paddingLeft = parseFloat(style.paddingLeft);
        const borderTop = parseFloat(style.borderTopWidth);
        const borderRight = parseFloat(style.borderRightWidth);
        const borderBottom = parseFloat(style.borderBottomWidth);
        const borderLeft = parseFloat(style.borderLeftWidth);

        const content = {
          x: rect.left + scrollX + borderLeft + paddingLeft,
          y: rect.top + scrollY + borderTop + paddingTop,
          width: rect.width - borderLeft - borderRight - paddingLeft - paddingRight,
          height: rect.height - borderTop - borderBottom - paddingTop - paddingBottom,
        };

        const padding = {
          x: rect.left + scrollX + borderLeft,
          y: rect.top + scrollY + borderTop,
          width: rect.width - borderLeft - borderRight,
          height: rect.height - borderTop - borderBottom,
        };

        const border = {
          x: rect.left + scrollX,
          y: rect.top + scrollY,
          width: rect.width,
          height: rect.height,
        };

        // Margin box
        const marginTop = parseFloat(style.marginTop);
        const marginRight = parseFloat(style.marginRight);
        const marginBottom = parseFloat(style.marginBottom);
        const marginLeft = parseFloat(style.marginLeft);

        const margin = {
          x: rect.left + scrollX - marginLeft,
          y: rect.top + scrollY - marginTop,
          width: rect.width + marginLeft + marginRight,
          height: rect.height + marginTop + marginBottom,
        };

        return { content, padding, border, margin };
      }, selector);

      if (!boxModel) {
        throw new Error(`Element not found: ${selector}`);
      }

      // Convert to quad format (4 points: top-left, top-right, bottom-right, bottom-left)
      const toQuad = (box: { x: number; y: number; width: number; height: number }) => [
        box.x, box.y,
        box.x + box.width, box.y,
        box.x + box.width, box.y + box.height,
        box.x, box.y + box.height,
      ];

      return {
        model: {
          content: toQuad(boxModel.content),
          padding: toQuad(boxModel.padding),
          border: toQuad(boxModel.border),
          margin: toQuad(boxModel.margin),
          width: boxModel.border.width,
          height: boxModel.border.height,
        },
      };
    }

    case 'scrollIntoViewIfNeeded': {
      const nodeId = params.nodeId as number;
      const selector = session.nodeMap.get(nodeId);

      if (!selector) throw new Error(`Node not found: ${nodeId}`);

      await page.evaluate((sel: string) => {
        const el = document.querySelector(sel);
        if (el) {
          el.scrollIntoView({ block: 'center', inline: 'center', behavior: 'instant' });
        }
      }, selector);

      return {};
    }

    case 'removeNode': {
      const nodeId = params.nodeId as number;
      const selector = session.nodeMap.get(nodeId);

      if (!selector) throw new Error(`Node not found: ${nodeId}`);

      await page.evaluate((sel: string) => {
        const el = document.querySelector(sel);
        if (el && el.parentNode) {
          el.parentNode.removeChild(el);
        }
      }, selector);

      session.nodeMap.delete(nodeId);
      return {};
    }

    case 'setNodeValue': {
      const nodeId = params.nodeId as number;
      const value = params.value as string;
      const selector = session.nodeMap.get(nodeId);

      if (!selector) throw new Error(`Node not found: ${nodeId}`);

      await page.evaluate((sel: string, val: string) => {
        const el = document.querySelector(sel);
        if (el) {
          el.textContent = val;
        }
      }, selector, value);

      return {};
    }

    case 'setFileInputFiles': {
      const nodeId = params.nodeId as number;
      const files = params.files as string[];
      const selector = session.nodeMap.get(nodeId);

      if (!selector) throw new Error(`Node not found: ${nodeId}`);

      const element = await page.$(selector);
      if (element) {
        // Cast to input element handle for uploadFile
        const inputElement = element as unknown as { uploadFile: (...paths: string[]) => Promise<void> };
        await inputElement.uploadFile(...files);
      }

      return {};
    }

    case 'enable':
    case 'disable':
      return {};

    default:
      throw new Error(`Unknown DOM method: ${command}`);
  }
}
