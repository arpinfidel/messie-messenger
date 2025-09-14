<script lang="ts">
  import { sasVerificationStore } from '@/viewmodels/matrix/core/SasVerificationStore';
  import { onDestroy } from 'svelte';
  import type { SasVerificationData } from '@/viewmodels/matrix/core/SasVerificationStore';

  let sas: SasVerificationData | null = null;
  const unsubscribe = sasVerificationStore.subscribe((value) => (sas = value));
  onDestroy(unsubscribe);

  function confirm() {
    sas?.confirm();
  }
  function cancel() {
    sas?.cancel();
  }
</script>

{#if sas}
  <div class="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50">
    <div class="rounded-lg bg-white p-6 shadow-lg dark:bg-gray-800">
      <h2 class="mb-4 text-lg font-semibold text-gray-900 dark:text-gray-100">Verify Emoji</h2>
      <div class="mb-4 flex justify-center text-4xl">
        {#each sas.emoji as [emoji, name]}
          <span class="mx-1" title={name}>{emoji}</span>
        {/each}
      </div>
      {#if sas.waiting}
        <p class="mb-4 text-center text-sm text-gray-600 dark:text-gray-300">
          Waiting for the other user…
        </p>
      {/if}
      <div class="flex justify-end gap-2">
        <button
          class="inline-flex justify-center rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 dark:border-gray-600 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600 dark:focus:ring-offset-gray-800"
          on:click={cancel}
        >
          Cancel
        </button>
        <button
          class="inline-flex justify-center rounded-md border border-transparent bg-indigo-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 dark:focus:ring-offset-gray-800 disabled:cursor-not-allowed disabled:opacity-50"
          on:click={confirm}
          disabled={sas.waiting}
        >
          Matches
        </button>
      </div>
    </div>
  </div>
{/if}
