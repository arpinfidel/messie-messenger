<script lang="ts">
  import { matrixSettings } from '../../viewmodels/matrix/MatrixSettings'
  import { MatrixViewModel } from '../../viewmodels/matrix/MatrixViewModel'

  const matrixViewModel = MatrixViewModel.getInstance()

  let recoveryKey: string = matrixSettings.recoveryKey

  function saveRecoveryKey() {
    matrixSettings.recoveryKey = recoveryKey
    console.log('Recovery Key saved to settings object.')
  }
</script>

<div class="matrix-settings-tab p-4">
  <h1 class="text-2xl font-bold mb-4">Matrix Settings</h1>
  <p class="mb-4">This is a placeholder for Matrix module settings.</p>

  <div class="mb-4">
    <label for="recovery-key" class="block text-sm font-medium text-gray-700"
      >Recovery Key</label
    >
    <input
      type="text"
      id="recovery-key"
      bind:value={recoveryKey}
      class="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
      placeholder="Enter your recovery key"
    />
  </div>

  <button
    on:click={saveRecoveryKey}
    class="inline-flex justify-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
  >
    Save Recovery Key
  </button>

  <button
    on:click={() =>
      matrixViewModel
        .verifyCurrentDevice()
        .then(() => console.log('Device verification initiated successfully.'))
        .catch((error) =>
          console.error('Error initiating device verification:', error)
        )}
    class="mt-4 inline-flex justify-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
  >
    Verify Device
  </button>
</div>
