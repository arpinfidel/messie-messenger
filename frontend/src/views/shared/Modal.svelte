<script lang="ts">
  import { createEventDispatcher, onDestroy } from 'svelte';
  import { tick } from 'svelte';

  export let show = false;
  export let closeOnEscape = true;
  export let closeOnBackdrop = true;
  export let containerClass =
    'relative w-full max-w-lg rounded-lg bg-white p-6 shadow-lg outline-none focus:outline-none dark:bg-gray-800';
  export let ariaLabel: string | null = null;
  export let ariaLabelledby: string | null = null;
  export let role: 'dialog' | 'alertdialog' = 'dialog';
  export let autoFocus = true;

  const dispatch = createEventDispatcher<{ close: void }>();

  let modalEl: HTMLDivElement | null = null;
  let previouslyFocused: Element | null = null;
  let previousBodyOverflow: string | null = null;
  let keyListenerAttached = false;

  function close() {
    dispatch('close');
  }

  function handleBackdropClick(event: MouseEvent) {
    if (closeOnBackdrop && event.target === event.currentTarget) {
      close();
    }
  }

  function handleKeydown(event: KeyboardEvent) {
    if (event.key === 'Escape' && closeOnEscape) {
      event.preventDefault();
      close();
    }
  }

  async function openModal() {
    previouslyFocused = document.activeElement;
    if (closeOnEscape && !keyListenerAttached) {
      document.addEventListener('keydown', handleKeydown);
      keyListenerAttached = true;
    }
    if (previousBodyOverflow === null) {
      previousBodyOverflow = document.body.style.overflow;
    }
    document.body.style.overflow = 'hidden';

    await tick();
    if (autoFocus && modalEl) {
      modalEl.focus({ preventScroll: true });
    }
  }

  function closeModal() {
    if (keyListenerAttached) {
      document.removeEventListener('keydown', handleKeydown);
      keyListenerAttached = false;
    }
    if (previousBodyOverflow !== null) {
      document.body.style.overflow = previousBodyOverflow;
      previousBodyOverflow = null;
    }
    const element = previouslyFocused as HTMLElement | null;
    previouslyFocused = null;
    if (element && typeof element.focus === 'function') {
      element.focus();
    }
  }

  $: {
    if (show) {
      void openModal();
    } else {
      closeModal();
    }
  }

  onDestroy(() => {
    closeModal();
  });
</script>

{#if show}
  <!-- svelte-ignore a11y-click-events-have-key-events -->
  <!-- svelte-ignore a11y-no-noninteractive-element-interactions -->
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
    role="presentation"
    on:click={handleBackdropClick}
  >
    <div
      bind:this={modalEl}
      class={containerClass}
      tabindex="-1"
      role={role}
      aria-modal="true"
      aria-label={ariaLabel ?? undefined}
      aria-labelledby={ariaLabelledby ?? undefined}
    >
      <slot name="header" {close} />
      <slot {close} />
      <slot name="footer" {close} />
    </div>
  </div>
{/if}
