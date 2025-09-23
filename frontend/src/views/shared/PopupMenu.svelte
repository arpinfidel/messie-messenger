<script lang="ts">
  import { createEventDispatcher, onMount, onDestroy, tick } from 'svelte';
  export let show: boolean = false;
  export let anchor: HTMLElement | null = null;
  const dispatch = createEventDispatcher<{ close: void }>();
  let menuEl: HTMLDivElement | null = null;
  let positionListenersAttached = false;

  function updatePosition() {
    if (!anchor || !menuEl) return;
    const rect = anchor.getBoundingClientRect();
    const menuRect = menuEl.getBoundingClientRect();
    const viewportWidth = document.documentElement.clientWidth;
    const viewportHeight = document.documentElement.clientHeight;

    let top = rect.bottom + window.scrollY + 4;
    let left = rect.left + window.scrollX;

    const rightOverflow = left + menuRect.width - (window.scrollX + viewportWidth - 8);
    if (rightOverflow > 0) {
      left = Math.max(window.scrollX + 8, left - rightOverflow);
    }

    const bottomOverflow = top + menuRect.height - (window.scrollY + viewportHeight - 8);
    if (bottomOverflow > 0) {
      const abovePosition = rect.top + window.scrollY - menuRect.height - 4;
      if (abovePosition >= window.scrollY + 8) {
        top = abovePosition;
      } else {
        top = Math.max(window.scrollY + 8, top - bottomOverflow);
      }
    }

    menuEl.style.top = `${top}px`;
    menuEl.style.left = `${left}px`;
  }

  function attachPositionListeners() {
    if (positionListenersAttached) return;
    window.addEventListener('resize', updatePosition);
    window.addEventListener('scroll', updatePosition, true);
    positionListenersAttached = true;
  }

  function detachPositionListeners() {
    if (!positionListenersAttached) return;
    window.removeEventListener('resize', updatePosition);
    window.removeEventListener('scroll', updatePosition, true);
    positionListenersAttached = false;
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
    detachPositionListeners();
  });

  $: if (show && anchor) {
    void tick().then(() => {
      updatePosition();
      attachPositionListeners();
    });
  } else {
    detachPositionListeners();
  }
</script>

{#if show}
  <div
    bind:this={menuEl}
    class="fixed z-50 rounded-lg border border-gray-200 bg-white p-2 shadow-lg dark:border-gray-700 dark:bg-gray-800"
  >
    <slot />
  </div>
{/if}

