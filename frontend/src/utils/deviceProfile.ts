import { readable } from 'svelte/store';

export type DeviceType = 'desktop' | 'tablet' | 'mobile';
export type Orientation = 'portrait' | 'landscape';

export type DeviceProfile = {
  device: DeviceType;
  orientation: Orientation;
  supportsSplitLayout: boolean;
};

const DEFAULT_PROFILE: DeviceProfile = {
  device: 'desktop',
  orientation: 'landscape',
  supportsSplitLayout: true,
};

function safeMatchMedia(query: string): boolean {
  if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') {
    return false;
  }
  try {
    return window.matchMedia(query).matches;
  } catch (error) {
    console.warn('[deviceProfile] matchMedia failed for query', query, error);
    return false;
  }
}

function getNavigator(): Navigator | null {
  if (typeof navigator === 'undefined') {
    return null;
  }
  return navigator;
}

function getViewportWidth(): number {
  if (typeof window === 'undefined') {
    return 0;
  }
  const docEl = typeof document !== 'undefined' ? document.documentElement : null;
  return (
    window.innerWidth ||
    docEl?.clientWidth ||
    (typeof window.screen !== 'undefined' ? window.screen.width : 0) ||
    0
  );
}

function getScreenDimensions(): { width: number; height: number } {
  if (typeof window === 'undefined' || typeof window.screen === 'undefined') {
    return { width: 0, height: 0 };
  }
  const { width = 0, height = 0 } = window.screen;
  return { width, height };
}

function getOrientationFromScreenApi(): Orientation | null {
  if (typeof window === 'undefined' || typeof window.screen === 'undefined') {
    return null;
  }

  const screenOrientation = window.screen.orientation;
  const orientationType = screenOrientation?.type;
  if (typeof orientationType === 'string') {
    if (orientationType.includes('portrait')) {
      return 'portrait';
    }
    if (orientationType.includes('landscape')) {
      return 'landscape';
    }
  }

  const legacyOrientation = (window as typeof window & { orientation?: number }).orientation;
  if (typeof legacyOrientation === 'number') {
    return Math.abs(legacyOrientation) === 90 ? 'landscape' : 'portrait';
  }

  return null;
}

function getOrientation(): Orientation {
  const apiOrientation = getOrientationFromScreenApi();
  if (apiOrientation) {
    return apiOrientation;
  }

  const { width: screenWidth, height: screenHeight } = getScreenDimensions();
  if (screenWidth > 0 && screenHeight > 0) {
    return screenWidth >= screenHeight ? 'landscape' : 'portrait';
  }

  if (safeMatchMedia('(orientation: portrait)')) {
    return 'portrait';
  }
  if (safeMatchMedia('(orientation: landscape)')) {
    return 'landscape';
  }

  if (typeof window !== 'undefined') {
    const innerWidth = window.innerWidth || window.outerWidth || 0;
    const innerHeight = window.innerHeight || window.outerHeight || 0;
    if (innerWidth > 0 && innerHeight > 0) {
      return innerWidth >= innerHeight ? 'landscape' : 'portrait';
    }
  }

  return DEFAULT_PROFILE.orientation;
}

function detectDeviceType(params: {
  hasHover: boolean;
  hasFinePointer: boolean;
  touchPoints: number;
  userAgent: string;
  platform: string;
}): DeviceType {
  const { hasHover, hasFinePointer, touchPoints, userAgent, platform } = params;

  const isIPadOS = /iPad|Macintosh/.test(userAgent) && touchPoints > 1;
  const isAndroidTablet = /Android/.test(userAgent) && !/Mobile/.test(userAgent);
  const isMobileUA = /Mobi|iPhone|iPod|Phone/.test(userAgent);
  const isDesktopPlatform = /Win|Mac|Linux|X11/.test(platform);

  if ((hasHover && hasFinePointer && !isIPadOS) || isDesktopPlatform) {
    return 'desktop';
  }

  if (isIPadOS || isAndroidTablet) {
    return 'tablet';
  }

  if (isMobileUA || touchPoints > 0) {
    return 'mobile';
  }

  return 'desktop';
}

function detectSplitLayout(device: DeviceType, width: number, orientation: Orientation): boolean {
  if (width === 0) {
    return DEFAULT_PROFILE.supportsSplitLayout;
  }

  const MIN_SPLIT_WIDTH = 768;

  if (device === 'mobile') {
    return false;
  }

  if (device === 'tablet') {
    return orientation === 'landscape';
  }

  return width >= MIN_SPLIT_WIDTH;
}

export function detectDeviceAndOrientation(): DeviceProfile {
  if (typeof window === 'undefined') {
    return DEFAULT_PROFILE;
  }

  const nav = getNavigator();
  const hasHover = safeMatchMedia('(hover: hover)');
  const hasFinePointer =
    safeMatchMedia('(pointer: fine)') || safeMatchMedia('(any-pointer: fine)');
  const touchPoints = nav?.maxTouchPoints ?? 0;
  const userAgent = nav?.userAgent ?? '';
  const platform = ((nav as any)?.userAgentData?.platform as string | undefined) ?? nav?.platform ?? '';

  const width = getViewportWidth();
  const orientation = getOrientation();

  const device = detectDeviceType({
    hasHover,
    hasFinePointer,
    touchPoints,
    userAgent,
    platform,
  });

  const supportsSplitLayout = detectSplitLayout(device, width, orientation);

  return {
    device,
    orientation,
    supportsSplitLayout,
  };
}

export const deviceProfile = readable<DeviceProfile>(DEFAULT_PROFILE, (set) => {
  if (typeof window === 'undefined') {
    return () => undefined;
  }

  const update = () => set(detectDeviceAndOrientation());

  const mediaQueries: Array<{ query: string; listener: ((event: MediaQueryListEvent) => void) | null; media: MediaQueryList | null }> = [];

  const registerQuery = (query: string) => {
    if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') {
      return;
    }
    const media = window.matchMedia(query);
    const handler = (event: MediaQueryListEvent) => {
      update();
    };
    media.addEventListener('change', handler);
    mediaQueries.push({ query, listener: handler, media });
  };

  registerQuery('(hover: hover)');
  registerQuery('(pointer: fine)');
  registerQuery('(any-pointer: fine)');
  registerQuery('(orientation: portrait)');
  registerQuery('(orientation: landscape)');

  const resizeHandler = () => update();
  const orientationHandler = () => update();

  window.addEventListener('resize', resizeHandler, { passive: true });
  window.addEventListener('orientationchange', orientationHandler, { passive: true });

  const userAgentData = (getNavigator() as any)?.userAgentData;
  const userAgentHandler = typeof userAgentData?.addEventListener === 'function'
    ? () => {
        update();
      }
    : null;

  if (userAgentHandler) {
    userAgentData.addEventListener('change', userAgentHandler);
  }

  update();

  return () => {
    window.removeEventListener('resize', resizeHandler);
    window.removeEventListener('orientationchange', orientationHandler);
    mediaQueries.forEach(({ media, listener }) => {
      if (media && listener) {
        media.removeEventListener('change', listener);
      }
    });
    if (userAgentHandler && userAgentData) {
      userAgentData.removeEventListener('change', userAgentHandler);
    }
  };
});

export default deviceProfile;
