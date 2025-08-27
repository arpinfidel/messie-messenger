<script lang="ts">
  import { createEventDispatcher } from 'svelte';

  export let show: boolean = false;
  export let tabs: { name: string; component: any }[] = [];

  let activeTabName: string = tabs.length > 0 ? tabs[0].name : '';

  const dispatch = createEventDispatcher();

  function closePopup() {
    show = false;
    dispatch('close');
  }

  $: if (tabs.length > 0 && !activeTabName) {
    activeTabName = tabs[0].name;
  }
</script>

{#if show}
  <div class="fixed inset-0 bg-gray-600 bg-opacity-50 flex items-center justify-center z-50">
    <div class="bg-white rounded-lg shadow-xl w-11/12 md:w-2/3 lg:w-1/2 max-h-[90vh] flex flex-col">
      <!-- Header -->
      <div class="px-6 py-4 border-b border-gray-200 flex justify-between items-center">
        <h2 class="text-xl font-semibold text-gray-800">Settings</h2>
        <button on:click={closePopup} class="text-gray-500 hover:text-gray-700">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>

      <!-- Tabs and Content -->
      <div class="flex flex-grow overflow-hidden">
        <!-- Tab Navigation -->
        <nav class="flex flex-col p-4 space-y-2 border-r border-gray-200 bg-gray-50">
          {#each tabs as tab}
            <button
              class="px-4 py-2 text-sm font-medium rounded-md text-left
                     {activeTabName === tab.name ? 'bg-blue-500 text-white' : 'text-gray-700 hover:bg-gray-200'}"
              on:click={() => (activeTabName = tab.name)}
            >
              {tab.name}
            </button>
          {/each}
        </nav>

        <!-- Tab Content -->
        <div class="flex-grow p-6 overflow-y-auto">
          {#each tabs as tab}
            {#if activeTabName === tab.name}
              <svelte:component this={tab.component} />
            {/if}
          {/each}
        </div>
      </div>
    </div>
  </div>
{/if}