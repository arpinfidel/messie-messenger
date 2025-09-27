<script lang="ts">
  import { matrixSettings } from '../../viewmodels/matrix/MatrixSettings';
  import { MatrixViewModel } from '../../viewmodels/matrix/MatrixViewModel';
  import SasVerificationModal from './components/SasVerificationModal.svelte';

  const matrixViewModel = MatrixViewModel.getInstance();

  let recoveryKey: string = matrixSettings.recoveryKey;
  // Cooldown is stored in milliseconds; edit as seconds in UI
  let notifyCooldownSeconds: number = Math.floor((matrixSettings.notifyCooldownMs || 0) / 1000);
  let verificationMessage: { type: 'success' | 'error'; text: string } | null = null;

  function saveSettings() {
    matrixSettings.recoveryKey = recoveryKey;
    // Persist cooldown (seconds -> ms)
    const ms = Math.max(0, Math.floor(Number(notifyCooldownSeconds) || 0)) * 1000;
    matrixSettings.saveNotifyCooldown(ms);
    console.log('Settings saved.');
  }

  async function verifyDevice() {
    verificationMessage = null;
    try {
      await matrixViewModel.verifyCurrentDevice();
      verificationMessage = {
        type: 'success',
        text: 'Device verification completed successfully.',
      };
    } catch (error) {
      console.error('Error initiating device verification:', error);
      const text =
        error instanceof Error && error.message
          ? error.message
          : 'Failed to start device verification. Check the console for details.';
      verificationMessage = { type: 'error', text };
    }
  }
</script>

<div class="matrix-settings-tab p-4">
  <h1 class="mb-4 text-2xl font-bold">Matrix Settings</h1>
  <p class="mb-4">This is a placeholder for Matrix module settings.</p>

  <div class="mb-4">
    <label for="recovery-key" class="block text-sm font-medium text-gray-700">Recovery Key</label>
    <input
      type="text"
      id="recovery-key"
      bind:value={recoveryKey}
      class="mt-1 block w-full rounded-md border border-gray-300 px-3 py-2 shadow-sm focus:border-indigo-500 focus:outline-none focus:ring-indigo-500 sm:text-sm"
      placeholder="Enter your recovery key"
    />
  </div>

  <div class="mb-4">
    <label for="notify-cooldown" class="block text-sm font-medium text-gray-700"
      >Notification Cooldown (per room)</label
    >
    <div class="mt-1 flex items-center gap-2">
      <input
        type="number"
        id="notify-cooldown"
        min="0"
        step="1"
        bind:value={notifyCooldownSeconds}
        class="block w-40 rounded-md border border-gray-300 px-3 py-2 shadow-sm focus:border-indigo-500 focus:outline-none focus:ring-indigo-500 sm:text-sm"
        placeholder="0"
      />
      <span class="text-sm text-gray-600">seconds (0 = always notify)</span>
    </div>
  </div>

  <button
    on:click={saveSettings}
    class="inline-flex justify-center rounded-md border border-transparent bg-indigo-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"
  >
    Save Settings
  </button>

  {#if verificationMessage}
    <div
      class={`mt-4 rounded-md border px-3 py-2 text-sm ${
        verificationMessage.type === 'success'
          ? 'border-green-300 bg-green-50 text-green-800'
          : 'border-red-300 bg-red-50 text-red-800'
      }`}
    >
      {verificationMessage.text}
    </div>
  {/if}

  <button
    on:click={verifyDevice}
    class="mt-4 inline-flex justify-center rounded-md border border-transparent bg-indigo-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"
  >
    Verify Device
  </button>

  <SasVerificationModal />
</div>
