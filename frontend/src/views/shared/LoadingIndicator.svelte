<script lang="ts">
  export let show: boolean;
  export let width: string = '100%'; // Used in fixed mode
  export let left: string = '0'; // Used in fixed mode
  export let text: string = '';
  export let mode: 'fixed' | 'inline' = 'fixed';
</script>

{#if show}
  <div class="loading-indicator {mode}" style="--width: {width}; --left: {left};">
    <div class="progress-bar"></div>
    {#if text}
      <span class="loading-text">{text}</span>
    {/if}
  </div>
{/if}

<style>
  .loading-indicator {
    height: 20px;
    background-color: #2196f3;
    overflow: hidden;
    display: flex;
    align-items: center;
    justify-content: center;
    color: white;
    font-size: 0.75rem;
    font-weight: bold;
    text-shadow: 1px 1px 2px rgba(0, 0, 0, 0.5);
  }

  /* Fixed (legacy) mode */
  .loading-indicator.fixed {
    position: fixed;
    bottom: 0;
    left: var(--left);
    width: var(--width);
    z-index: 1000;
  }

  /* Inline/sticky mode for sidebar */
  .loading-indicator.inline {
    position: sticky;
    bottom: 0;
    left: 0;
    width: 100%;
    z-index: 10; /* enough to sit above list items within the column */
  }

  .progress-bar {
    position: absolute;
    height: 100%;
    width: 100%; /* Full width of the container */
    background-color: #2196f3; /* Base color */
    z-index: 1; /* Behind text */
  }

  .progress-bar::before {
    content: '';
    position: absolute;
    height: 100%;
    width: 30%;
    background-color: #007bff;
    animation: indeterminate-progress 1.5s infinite ease-in-out;
  }

  .loading-text {
    position: relative; /* To bring text above the progress bar */
    z-index: 2;
  }

  @keyframes indeterminate-progress {
    0% {
      left: -30%;
    }
    100% {
      left: 100%;
    }
  }
</style>
