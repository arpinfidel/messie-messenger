<script lang="ts">
  import { createEventDispatcher } from 'svelte';

  export let ariaLabel = 'Close dialog';
  export let variant: 'light' | 'dark' = 'dark';
  export let iconClass = 'h-6 w-6';
  export let type: 'button' | 'submit' | 'reset' = 'button';

  const dispatch = createEventDispatcher();

  let restClass = '';
  let restProps: Record<string, any> = {};

  $: ({ class: restClass = '', ...restProps } = $$restProps);

  $: variantClass =
    variant === 'light'
      ? 'text-gray-500 hover:text-gray-700 focus:ring-indigo-500 focus:ring-offset-white'
      : 'text-gray-400 hover:text-gray-200 focus:ring-indigo-500 focus:ring-offset-gray-900';

  function handleClick(event: MouseEvent) {
    dispatch('click', event);
  }
</script>

<button
  type={type}
  aria-label={ariaLabel}
  class={`rounded p-1 transition-colors focus:outline-none focus:ring-2 focus:ring-offset-2 ${variantClass} ${restClass}`.trim()}
  on:click={handleClick}
  {...restProps}
>
  <svg
    xmlns="http://www.w3.org/2000/svg"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    stroke-width="2"
    stroke-linecap="round"
    stroke-linejoin="round"
    class={iconClass}
    aria-hidden="true"
  >
    <path d="M6 18L18 6M6 6l12 12" />
  </svg>
</button>
