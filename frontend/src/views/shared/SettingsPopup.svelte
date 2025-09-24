<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  import Modal from './Modal.svelte';

  export let show: boolean = false;
  export let tabs: { name: string; component: any }[] = [];

  let activeTabName: string = tabs.length > 0 ? tabs[0].name : '';

  const dispatch = createEventDispatcher();

  function closePopup() {
    show = false;
    dispatch('close');
  }

  $: {
    if (tabs.length === 0) {
      activeTabName = '';
    } else if (!tabs.some((tab) => tab.name === activeTabName)) {
      activeTabName = tabs[0].name;
    }
  }
</script>

<Modal
  show={show}
  on:close={closePopup}
  ariaLabelledby="settings-modal-title"
  containerClass="relative flex max-h-[90vh] w-11/12 flex-col rounded-xl border border-gray-700 bg-gray-900 text-gray-100 shadow-2xl md:w-2/3 lg:w-1/2"
  title="Settings"
  showCloseButton
  closeButtonLabel="Close settings"
>
  <div class="flex flex-grow overflow-hidden">
    <nav class="flex flex-col space-y-2 border-r border-gray-700 bg-gray-800 p-4">
      {#each tabs as tab}
        <button
          class="rounded-md px-4 py-2 text-left text-sm font-medium transition-colors {activeTabName === tab.name
            ? 'bg-blue-600 text-white'
            : 'text-gray-300 hover:bg-gray-700'}"
          on:click={() => (activeTabName = tab.name)}
        >
          {tab.name}
        </button>
      {/each}
    </nav>

    <div class="flex-grow overflow-y-auto bg-gray-900 p-6 text-gray-100">
      {#each tabs as tab}
        {#if activeTabName === tab.name}
          <svelte:component this={tab.component} />
        {/if}
      {/each}
    </div>
  </div>
</Modal>
