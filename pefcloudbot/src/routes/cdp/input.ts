import type { Page } from '@cloudflare/puppeteer';

/**
 * Input domain handlers
 */
export async function handleInput(
  page: Page,
  command: string,
  params: Record<string, unknown>
): Promise<unknown> {
  switch (command) {
    case 'dispatchMouseEvent': {
      const type = params.type as string;
      const x = params.x as number;
      const y = params.y as number;
      const button = (params.button as string) || 'left';
      const clickCount = (params.clickCount as number) || 1;

      const mouse = page.mouse;

      switch (type) {
        case 'mousePressed':
          await mouse.down({ button: button as 'left' | 'right' | 'middle' });
          break;
        case 'mouseReleased':
          await mouse.up({ button: button as 'left' | 'right' | 'middle' });
          break;
        case 'mouseMoved':
          await mouse.move(x, y);
          break;
        case 'mouseWheel':
          await mouse.wheel({ deltaX: params.deltaX as number, deltaY: params.deltaY as number });
          break;
        default:
          // For click, do move + down + up
          await mouse.click(x, y, {
            button: button as 'left' | 'right' | 'middle',
            clickCount,
          });
      }

      return {};
    }

    case 'dispatchKeyEvent': {
      const type = params.type as string;
      const key = params.key as string;
      const text = params.text as string;

      const keyboard = page.keyboard;

      // Type assertion needed as CDP uses string keys while Puppeteer uses KeyInput
      type KeyInput = Parameters<typeof keyboard.down>[0];

      switch (type) {
        case 'keyDown':
          await keyboard.down(key as KeyInput);
          break;
        case 'keyUp':
          await keyboard.up(key as KeyInput);
          break;
        case 'char':
          if (text) await keyboard.type(text);
          break;
        default:
          if (key) await keyboard.press(key as KeyInput);
      }

      return {};
    }

    case 'insertText': {
      const text = params.text as string;
      if (text) {
        await page.keyboard.type(text);
      }
      return {};
    }

    default:
      throw new Error(`Unknown Input method: ${command}`);
  }
}
