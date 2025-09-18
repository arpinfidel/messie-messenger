<script lang="ts">
  import { onMount } from 'svelte';
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
  import { EmailViewModel } from './viewmodels/email/EmailViewModel';
  const emailViewModel = EmailViewModel.getInstance();
  let timelineWidth: number = 0;
  let timelineLeft: number = 0;
  let timelineContainer: HTMLDivElement;

  let selectedTimelineItem: any = null;
  let matrixViewModel: MatrixViewModel;
  let showSettingsPopup: boolean = false;
  let loggedIn = false;
  let loginStateChecked = false; // avoid showing overlay until init completes
  let showForgotPassword = false;

  // Matrix login handled via MatrixLogin component now

  onMount(async () => {
    matrixViewModel = MatrixViewModel.getInstance(); // Use the singleton instance
    await matrixViewModel.initialize();
    loggedIn = matrixViewModel.isLoggedIn();
    loginStateChecked = true;

    const params = new URLSearchParams(window.location.search);
    // If redirected back with a sid from the homeserver, show reset UI
    if (params.get('sid')) {
      showForgotPassword = true;
    }

    window.addEventListener('messie-open-room', (e: Event) => {
      const roomId = (e as CustomEvent<string>).detail;
      const items = get(matrixViewModel.getTimelineItems());
      const item = items.find((it) => it.id === roomId);
      if (item) {
        selectedTimelineItem = item;
      }
    });
  });

  $: if (timelineContainer) {
    timelineLeft = timelineContainer.offsetLeft;
  }
  function handleTimelineItemSelected(event: CustomEvent) {
    selectedTimelineItem = event.detail;
    if (selectedTimelineItem?.type === 'email') {
      void emailViewModel.handleTimelineSelection(selectedTimelineItem);
    }
  }
</script>

<main class="grid h-screen grid-cols-[1fr_2fr] bg-gray-900">
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
    <DetailPanel selectedItem={selectedTimelineItem} />
  </div>
</main>

<SettingsPopup
  show={showSettingsPopup}
  on:close={() => (showSettingsPopup = false)}
  tabs={[
    { name: 'Matrix', component: MatrixSettingsTab },
    { name: 'Cloud Auth', component: CloudAuthTab },
    { name: 'Email', component: EmailLoginTab },
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

<style>
  /* Your existing styles */
</style>
