import type { Page } from '@cloudflare/puppeteer';

/**
 * Emulation domain handlers
 */
export async function handleEmulation(
  page: Page,
  command: string,
  params: Record<string, unknown>
): Promise<unknown> {
  switch (command) {
    case 'setDeviceMetricsOverride': {
      const width = params.width as number;
      const height = params.height as number;
      const deviceScaleFactor = (params.deviceScaleFactor as number) || 1;
      const mobile = (params.mobile as boolean) || false;

      await page.setViewport({
        width,
        height,
        deviceScaleFactor,
        isMobile: mobile,
      });

      return {};
    }

    case 'setUserAgentOverride': {
      const userAgent = params.userAgent as string;
      await page.setUserAgent(userAgent);
      return {};
    }

    case 'clearDeviceMetricsOverride':
      // Reset to default
      await page.setViewport({ width: 1280, height: 720 });
      return {};

    case 'setGeolocationOverride': {
      const latitude = params.latitude as number | undefined;
      const longitude = params.longitude as number | undefined;
      const accuracy = params.accuracy as number | undefined;

      if (latitude !== undefined && longitude !== undefined) {
        await page.setGeolocation({
          latitude,
          longitude,
          accuracy: accuracy ?? 100,
        });
      }

      return {};
    }

    case 'clearGeolocationOverride': {
      // Can't truly clear, but we can set to a default
      return {};
    }

    case 'setTimezoneOverride': {
      const timezoneId = params.timezoneId as string;

      // Puppeteer doesn't have direct timezone override, but we can emulate via evaluate
      await page.evaluateOnNewDocument((tz: string) => {
        // Override Date to use the specified timezone
        const originalDate = Date;
        const originalToString = Date.prototype.toString;
        const originalToLocaleString = Date.prototype.toLocaleString;

        Date.prototype.toString = function() {
          return originalToLocaleString.call(this, 'en-US', { timeZone: tz });
        };

        // Store timezone for scripts that check it
        (globalThis as unknown as Record<string, string>).__timezone = tz;
      }, timezoneId);

      return {};
    }

    case 'setTouchEmulationEnabled': {
      const enabled = params.enabled as boolean;

      // Puppeteer handles this via viewport isMobile, but we can also inject touch events
      if (enabled) {
        await page.evaluateOnNewDocument(() => {
          // Make the browser think it supports touch
          Object.defineProperty(navigator, 'maxTouchPoints', {
            get: () => 1,
          });

          // Add touch event support indicator
          window.ontouchstart = null;
        });
      }

      return {};
    }

    case 'setEmulatedMedia': {
      const media = params.media as string | undefined;
      const features = params.features as Array<{ name: string; value: string }> | undefined;

      if (media) {
        await page.emulateMediaType(media as 'screen' | 'print');
      }

      if (features) {
        await page.emulateMediaFeatures(
          features.map(f => ({ name: f.name, value: f.value }))
        );
      }

      return {};
    }

    case 'setDefaultBackgroundColorOverride': {
      const color = params.color as { r: number; g: number; b: number; a?: number } | undefined;

      if (color) {
        const { r, g, b, a = 1 } = color;
        await page.evaluate((rgba: string) => {
          document.documentElement.style.backgroundColor = rgba;
        }, `rgba(${r}, ${g}, ${b}, ${a})`);
      }

      return {};
    }

    default:
      throw new Error(`Unknown Emulation method: ${command}`);
  }
}
