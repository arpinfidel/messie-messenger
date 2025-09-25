<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import { get } from 'svelte/store';
  import UnifiedTimeline from './views/shared/UnifiedTimeline.svelte';
  import DetailPanel from './views/shared/DetailPanel.svelte';
  import { MatrixViewModel } from './viewmodels/matrix/MatrixViewModel';
  import SettingsPopup from './views/shared/SettingsPopup.svelte';
  import MatrixSettingsTab from './views/matrix/MatrixSettingsTab.svelte';
  import CloudAuthTab from './views/auth/CloudAuthTab.svelte';
  import MatrixLogin from './views/matrix/MatrixLogin.svelte';
  import MatrixForgotPassword from './views/matrix/MatrixForgotPassword.svelte';
  import EmailLoginTab from './views/email/EmailLoginTab.svelte';
  import { registerBackButtonHandler } from './utils/backButtonManager';
  import { EmailViewModel } from './viewmodels/email/EmailViewModel';
  import DeveloperSettingsTab from './views/settings/DeveloperSettingsTab.svelte';
  import { developerSettings } from './viewmodels/settings/DeveloperSettings';
  const emailViewModel = EmailViewModel.getInstance();
  const emailLoginStatusStore = emailViewModel.getLoginStatus();
  const emailLoginErrorStore = emailViewModel.getLoginError();
  const emailMailboxStatusStore = emailViewModel.getMailboxStatus();
  let timelineWidth: number = 0;
  let timelineLeft: number = 0;
  let timelineContainer: HTMLDivElement;

  let selectedTimelineItem: any = null;
  let matrixViewModel: MatrixViewModel;
  let showSettingsPopup: boolean = false;
  let loggedIn = false;
  let loginStateChecked = false; // avoid showing overlay until init completes
  let showForgotPassword = false;
  let isMobile = false;
  let detailHistoryActive = false;
  let mediaQuery: MediaQueryList | null = null;
  let unregisterDetailBack: (() => void) | null = null;
  let unregisterSettingsBack: (() => void) | null = null;
  let unregisterForgotBack: (() => void) | null = null;

  const rawBuildTimestamp = typeof __BUILD_TIMESTAMP__ === 'undefined' ? '' : __BUILD_TIMESTAMP__;

  const buildTimestampLabel = (() => {
    if (!rawBuildTimestamp) return '';
    const parsed = new Date(rawBuildTimestamp);
    if (Number.isNaN(parsed.getTime())) return '';
    const hours = parsed.getHours().toString().padStart(2, '0');
    const minutes = parsed.getMinutes().toString().padStart(2, '0');
    return `${hours}:${minutes}`;
  })();

  function ensureDetailHistory() {
    if (typeof window === 'undefined' || detailHistoryActive) return;
    const baseState = window.history.state;
    const nextState =
      baseState && typeof baseState === 'object'
        ? { ...baseState, messieDetail: true }
        : { messieDetail: true };
    window.history.pushState(nextState, '', window.location.href);
    detailHistoryActive = true;
  }

  function selectTimelineItem(
    item: any,
    options: {
      fromHistory?: boolean;
    } = {}
  ) {
    const fromHistory = options.fromHistory ?? false;
    selectedTimelineItem = item;
    if (item?.type === 'email') {
      void emailViewModel.handleTimelineSelection(item);
    }

    if (item) {
      if (!fromHistory && isMobile) {
        ensureDetailHistory();
      }
    } else {
      detailHistoryActive = false;
    }
  }

  function handleDetailClose() {
    if (typeof window !== 'undefined' && detailHistoryActive) {
      window.history.back();
      return;
    }
    selectTimelineItem(null);
  }

  $: {
    if (selectedTimelineItem) {
      unregisterDetailBack?.();
      unregisterDetailBack = registerBackButtonHandler(() => {
        handleDetailClose();
        return true;
      });
    } else {
      unregisterDetailBack?.();
      unregisterDetailBack = null;
    }
  }

  $: {
    if (showSettingsPopup) {
      unregisterSettingsBack?.();
      unregisterSettingsBack = registerBackButtonHandler(() => {
        showSettingsPopup = false;
        return true;
      });
    } else {
      unregisterSettingsBack?.();
      unregisterSettingsBack = null;
    }
  }

  $: {
    if (showForgotPassword) {
      unregisterForgotBack?.();
      unregisterForgotBack = registerBackButtonHandler(() => {
        showForgotPassword = false;
        if (typeof window !== 'undefined') {
          window.history.replaceState({}, '', window.location.pathname);
        }
        return true;
      });
    } else {
      unregisterForgotBack?.();
      unregisterForgotBack = null;
    }
  }

  // Matrix login handled via MatrixLogin component now

  onMount(() => {
    matrixViewModel = MatrixViewModel.getInstance(); // Use the singleton instance

    void (async () => {
      await matrixViewModel.initialize();
      loggedIn = matrixViewModel.isLoggedIn();
      loginStateChecked = true;

      const params = new URLSearchParams(window.location.search);
      // If redirected back with a sid from the homeserver, show reset UI
      if (params.get('sid')) {
        showForgotPassword = true;
      }
    })();

    const openRoomHandler = (e: Event) => {
      const roomId = (e as CustomEvent<string>).detail;
      const items = get(matrixViewModel.getTimelineItems());
      const item = items.find((it) => it.id === roomId);
      if (item) {
        selectTimelineItem(item);
      }
    };

    window.addEventListener('messie-open-room', openRoomHandler);

    const applyIsMobile = (matches: boolean) => {
      isMobile = matches;
      if (matches && selectedTimelineItem) {
        ensureDetailHistory();
      }
    };

    const mediaChangeHandler = (event: MediaQueryListEvent) => {
      applyIsMobile(event.matches);
    };

    if (typeof window !== 'undefined') {
      mediaQuery = window.matchMedia('(max-width: 768px)');
      applyIsMobile(mediaQuery.matches);
      mediaQuery.addEventListener('change', mediaChangeHandler);

      const popStateHandler = () => {
        if (detailHistoryActive) {
          selectTimelineItem(null, { fromHistory: true });
        }
      };

      window.addEventListener('popstate', popStateHandler);

      return () => {
        window.removeEventListener('messie-open-room', openRoomHandler);
        mediaQuery?.removeEventListener('change', mediaChangeHandler);
        window.removeEventListener('popstate', popStateHandler);
      };
    }

    return () => {
      window.removeEventListener('messie-open-room', openRoomHandler);
    };
  });

  onDestroy(() => {
    unregisterDetailBack?.();
    unregisterSettingsBack?.();
    unregisterForgotBack?.();
  });

  $: if (timelineContainer) {
    timelineLeft = timelineContainer.offsetLeft;
  }
  function handleTimelineItemSelected(event: CustomEvent) {
    selectTimelineItem(event.detail);
  }
</script>

<main class={`h-screen bg-gray-900 ${isMobile ? 'flex flex-col' : 'grid grid-cols-[1fr_2fr]'}`}>
  {#if !isMobile}
    <div
      class="overflow-y-auto overflow-x-hidden border-r border-gray-800"
      bind:clientWidth={timelineWidth}
      bind:this={timelineContainer}
    >
      <UnifiedTimeline
        on:itemSelected={handleTimelineItemSelected}
        on:openSettings={() => (showSettingsPopup = true)}
      />
    </div>
    <div class="flex h-full flex-col overflow-auto">
      <DetailPanel selectedItem={selectedTimelineItem} on:close={handleDetailClose} />
    </div>
  {:else}
    {#if !selectedTimelineItem}
      <div
        class="flex-1 overflow-y-auto overflow-x-hidden"
        bind:clientWidth={timelineWidth}
        bind:this={timelineContainer}
      >
        <UnifiedTimeline
          on:itemSelected={handleTimelineItemSelected}
          on:openSettings={() => (showSettingsPopup = true)}
        />
      </div>
    {:else}
      <div class="flex h-full flex-col overflow-auto">
        <DetailPanel selectedItem={selectedTimelineItem} on:close={handleDetailClose} />
      </div>
    {/if}
  {/if}
</main>

<SettingsPopup
  show={showSettingsPopup}
  on:close={() => (showSettingsPopup = false)}
  tabs={[
    { name: 'Matrix', component: MatrixSettingsTab },
    { name: 'Cloud Auth', component: CloudAuthTab },
    { name: 'Email', component: EmailLoginTab },
    { name: 'Developer', component: DeveloperSettingsTab },
  ]}
/>

{#if loginStateChecked && !loggedIn}
  <div class="fixed inset-0 z-50 bg-gray-900">
    {#if showForgotPassword}
      <MatrixForgotPassword
        on:done={() => {
          showForgotPassword = false;
          window.history.replaceState({}, '', window.location.pathname);
        }}
        on:cancel={() => {
          showForgotPassword = false;
          window.history.replaceState({}, '', window.location.pathname);
        }}
      />
    {:else}
      <MatrixLogin
        on:login={async (e) => {
          const { homeserverUrl, username, password, onError, onDone } = e.detail;
          try {
            await matrixViewModel.login(homeserverUrl, username, password);
            loggedIn = matrixViewModel.isLoggedIn();
            loginStateChecked = true;
          } catch (err) {
            console.error('Matrix login failed in App:', err);
            const msg =
              err instanceof Error ? err.message : typeof err === 'string' ? err : undefined;
            onError?.(msg || 'Login failed. Check details.');
          } finally {
            onDone?.();
          }
        }}
        on:forgot={() => (showForgotPassword = true)}
      />
    {/if}
  </div>
{/if}

{#if $emailLoginStatusStore === 'error' && $emailLoginErrorStore}
  <div class="fixed bottom-4 right-4 z-50 max-w-md rounded-md bg-red-600 px-4 py-3 text-sm text-white shadow-lg">
    Email connection error: {$emailLoginErrorStore}
  </div>
{/if}

{#if $emailMailboxStatusStore === 'refreshing'}
  <div class="fixed bottom-4 left-4 z-40 rounded-md bg-gray-900/90 px-4 py-2 text-sm text-gray-100 shadow-lg">
    Syncing email mailboxes…
  </div>
{/if}

{#if $developerSettings.showBuildTimestamp && buildTimestampLabel}
  <div class="pointer-events-none fixed bottom-3 right-3 z-50 rounded-md bg-gray-900/80 px-2 py-1 text-[0.7rem] font-medium uppercase tracking-wide text-gray-300 shadow-lg">
    Build {buildTimestampLabel}
  </div>
{/if}

<style>
  /* Your existing styles */
</style>
