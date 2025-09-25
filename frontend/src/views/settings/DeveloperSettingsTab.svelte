<script lang="ts">
  import {
    developerSettings,
    setBuildTimestampVisibility,
    setErudaEnabled,
  } from '@/viewmodels/settings/DeveloperSettings';

  let enableEruda = false;
  let showBuildTimestamp = false;

  $: enableEruda = $developerSettings.enableEruda;
  $: showBuildTimestamp = $developerSettings.showBuildTimestamp;

  function handleErudaChange(event: Event) {
    const target = event.currentTarget as HTMLInputElement | null;
    if (!target) return;
    setErudaEnabled(target.checked);
  }

  function handleBuildTimestampChange(event: Event) {
    const target = event.currentTarget as HTMLInputElement | null;
    if (!target) return;
    setBuildTimestampVisibility(target.checked);
  }
</script>

<div class="developer-settings-tab space-y-6">
  <div>
    <h1 class="text-2xl font-bold">Developer Settings</h1>
    <p class="text-sm text-gray-400">
      Enable diagnostics and debugging helpers directly on the device.
    </p>
  </div>

  <div class="rounded-lg border border-gray-700 bg-gray-800 p-4">
    <label class="flex items-start gap-3">
      <input
        type="checkbox"
        class="mt-1 h-4 w-4 rounded border-gray-600 bg-gray-900 text-blue-500 focus:ring-blue-500"
        checked={enableEruda}
        on:change={handleErudaChange}
      />
      <span>
        <span class="block text-sm font-medium text-gray-100">Enable Eruda console</span>
        <span class="mt-1 block text-xs text-gray-400">
          Adds a floating button that opens the Eruda developer console so you can
          inspect logs, network requests, and storage without connecting the device to a
          computer. Disable when you are done debugging to remove the overlay.
        </span>
      </span>
    </label>
  </div>

  <div class="rounded-lg border border-gray-700 bg-gray-800 p-4">
    <label class="flex items-start gap-3">
      <input
        type="checkbox"
        class="mt-1 h-4 w-4 rounded border-gray-600 bg-gray-900 text-blue-500 focus:ring-blue-500"
        checked={showBuildTimestamp}
        on:change={handleBuildTimestampChange}
      />
      <span>
        <span class="block text-sm font-medium text-gray-100">Show build timestamp overlay</span>
        <span class="mt-1 block text-xs text-gray-400">
          Displays the build timestamp (hour:minute) as a floating label in the corner for
          quick debugging checks. The overlay ignores pointer events.
        </span>
      </span>
    </label>
  </div>
</div>

<style>
  .developer-settings-tab {
    max-width: 32rem;
  }
</style>
