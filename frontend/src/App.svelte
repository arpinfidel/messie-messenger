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
  let timelineWidth: number = 0;
  let timelineLeft: number = 0;
  let timelineContainer: HTMLDivElement;

  let selectedTimelineItem: any = null;
  let matrixViewModel: MatrixViewModel;
  let showSettingsPopup: boolean = false;
  let loggedIn = false;
  let loginStateChecked = false; // avoid showing overlay until init completes

  // Matrix login handled via MatrixLogin component now

  onMount(async () => {
    matrixViewModel = MatrixViewModel.getInstance(); // Use the singleton instance
    await matrixViewModel.initialize();
    loggedIn = matrixViewModel.isLoggedIn();
    loginStateChecked = true;

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
  ]}
/>

{#if loginStateChecked && !loggedIn}
  <div class="fixed inset-0 z-50 bg-gray-900">
    <MatrixLogin
      on:login={async (e) => {
        const { homeserverUrl, username, password, onError, onDone } = e.detail;
        try {
          await matrixViewModel.login(homeserverUrl, username, password);
          loggedIn = matrixViewModel.isLoggedIn();
          loginStateChecked = true;
        } catch (err) {
          console.error('Matrix login failed in App:', err);
          const msg = err instanceof Error
            ? err.message
            : typeof err === 'string'
            ? err
            : undefined;
          onError?.(msg || 'Login failed. Check details.');
        } finally {
          onDone?.();
        }
      }}
    />
  </div>
{/if}

<style>
  /* Your existing styles */
</style>
