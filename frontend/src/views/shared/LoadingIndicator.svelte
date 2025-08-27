<script lang="ts">
    export let show: boolean;
    export let width: string = '100%'; // Default to full width
    export let left: string = '0'; // Default to left edge
    export let text: string = ''; // New prop for loading text
</script>

{#if show}
    <div class="loading-indicator" style="--width: {width}; --left: {left};">
        <div class="progress-bar"></div>
        {#if text}
            <span class="loading-text">{text}</span>
        {/if}
    </div>
{/if}

<style>
    .loading-indicator {
        position: fixed;
        bottom: 0;
        left: var(--left); /* Use CSS variable */
        width: var(--width); /* Use CSS variable */
        height: 20px; /* Increased height to accommodate text */
        background-color: #2196F3;
        z-index: 1000;
        overflow: hidden;
        display: flex; /* For centering text */
        align-items: center;
        justify-content: center;
        color: white; /* Text color */
        font-size: 0.75rem; /* Small text */
        font-weight: bold;
        text-shadow: 1px 1px 2px rgba(0,0,0,0.5);
    }

    .progress-bar {
        position: absolute;
        height: 100%;
        width: 100%; /* Full width of the container */
        background-color: #2196F3; /* Base color */
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
        0% { left: -30%; }
        100% { left: 100%; }
    }
</style>