<script lang="ts">
  import { onMount } from 'svelte';
  import UnifiedTimeline from './components/UnifiedTimeline.svelte';
  import DetailPanel from './components/DetailPanel.svelte';
  import { MatrixViewModel } from './lib/matrix/MatrixViewModel';
  import SettingsPopup from './modules/shared/components/SettingsPopup.svelte';
  import MatrixSettingsTab from './modules/matrix/components/MatrixSettingsTab.svelte';

  let selectedTimelineItem: any = null;
  let matrixViewModel: MatrixViewModel;
  let showSettingsPopup: boolean = false;

  // Temporary hardcoded credentials or prompt for them
  let homeserverUrl: string = localStorage.getItem('matrixHomeserverUrl') || 'https://matrix.org';
  let username: string = localStorage.getItem('matrixUsername') || '';
  let password: string = '';

  onMount(async () => {
    matrixViewModel = MatrixViewModel.getInstance(); // Use the singleton instance
    await matrixViewModel.initialize();

    // Part 1.1: Add placeholder for Matrix login
    if (!matrixViewModel.isLoggedIn()) { // Assuming a method to check login status exists or can be added
      homeserverUrl = prompt('Enter Matrix Homeserver URL:', homeserverUrl) || homeserverUrl;
      username = prompt('Enter Matrix Username:', username) || username;
      password = prompt('Enter Matrix Password:', '') || '';

      localStorage.setItem('matrixHomeserverUrl', homeserverUrl);
      localStorage.setItem('matrixUsername', username);

      try {
        await matrixViewModel.login(homeserverUrl, username, password);
        console.log('Matrix login successful in App.svelte');
      } catch (error) {
        console.error('Matrix login failed in App.svelte:', error);
        alert('Matrix login failed. Check console for details.');
      }
    }
  });

  function handleTimelineItemSelected(event: CustomEvent) {
    selectedTimelineItem = event.detail;
  }
</script>

<main class="flex h-screen bg-gray-100">
  <UnifiedTimeline on:itemSelected={handleTimelineItemSelected} on:openSettings={() => showSettingsPopup = true} />
  <DetailPanel selectedItem={selectedTimelineItem} />
</main>

<SettingsPopup show={showSettingsPopup} on:close={() => showSettingsPopup = false} tabs={[
  { name: 'Matrix', component: MatrixSettingsTab }
]} />

<style>
  /* Your existing styles */
</style>
