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
  <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
    <div class="flex max-h-[90vh] w-11/12 flex-col rounded-xl border border-gray-700 bg-gray-900 text-gray-100 shadow-2xl md:w-2/3 lg:w-1/2">
      <!-- Header -->
      <div class="flex items-center justify-between border-b border-gray-700 px-6 py-4">
        <h2 class="text-xl font-semibold">Settings</h2>
        <button on:click={closePopup} class="text-gray-400 hover:text-gray-200">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-6 w-6"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M6 18L18 6M6 6l12 12"
            />
          </svg>
        </button>
      </div>

      <!-- Tabs and Content -->
      <div class="flex flex-grow overflow-hidden">
        <!-- Tab Navigation -->
        <nav class="flex flex-col space-y-2 border-r border-gray-700 bg-gray-800 p-4">
          {#each tabs as tab}
            <button
              class="rounded-md px-4 py-2 text-left text-sm font-medium transition-colors
                     {activeTabName === tab.name
                ? 'bg-blue-600 text-white'
                : 'text-gray-300 hover:bg-gray-700'}"
              on:click={() => (activeTabName = tab.name)}
            >
              {tab.name}
            </button>
          {/each}
        </nav>

        <!-- Tab Content -->
        <div class="flex-grow overflow-y-auto p-6 bg-gray-900 text-gray-100">
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
