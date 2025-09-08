<script lang="ts">
  import { createEventDispatcher, onMount, onDestroy } from 'svelte';
  export let show: boolean = false;
  export let anchor: HTMLElement | null = null;
  const dispatch = createEventDispatcher<{ close: void }>();
  let menuEl: HTMLDivElement;

  function updatePosition() {
    if (!anchor || !menuEl) return;
    const rect = anchor.getBoundingClientRect();
    menuEl.style.top = `${rect.bottom + window.scrollY + 4}px`;
    menuEl.style.left = `${rect.left + window.scrollX}px`;
  }

  function handleClickOutside(event: MouseEvent) {
    if (
      show &&
      menuEl &&
      !menuEl.contains(event.target as Node) &&
      anchor &&
      !anchor.contains(event.target as Node)
    ) {
      dispatch('close');
    }
  }

  onMount(() => {
    document.addEventListener('click', handleClickOutside, true);
  });

  onDestroy(() => {
    document.removeEventListener('click', handleClickOutside, true);
  });

  $: if (show) updatePosition();
</script>

{#if show}
  <div
    bind:this={menuEl}
    class="fixed z-50 rounded-lg border border-gray-200 bg-white p-2 shadow-lg dark:border-gray-700 dark:bg-gray-800"
  >
    <slot />
  </div>
{/if}

