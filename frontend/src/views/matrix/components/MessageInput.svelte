<script lang="ts">
  import { createEventDispatcher } from 'svelte';

  export let isSending: boolean = false;
  export let className: string = '';

  const dispatch = createEventDispatcher<{ send: string }>();

  let text = '';
  const canSend = text.trim().length > 0 && !isSending;

  function trySend() {
    const content = text.trim();
    if (!content || isSending) return;
    dispatch('send', content);
    text = '';
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      trySend();
    }
  }
</script>

<div class="message-input-container {className}">
  <div class="input-wrapper">
    <textarea
      bind:value={text}
      on:keydown={handleKeydown}
      placeholder="Type your message... (Shift+Enter for new line)"
      class="message-input"
      rows="1"
      disabled={isSending}
    ></textarea>
    
    <button
      on:click={trySend}
      disabled={!canSend}
      class="send-button {canSend ? 'enabled' : 'disabled'}"
      title={isSending ? 'Sending...' : 'Send message'}
    >
      {#if isSending}
        <div class="loading-spinner small"></div>
      {:else}
        <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8" />
        </svg>
      {/if}
    </button>
  </div>

  <div class="input-helper">
    <span class="text-xs text-gray-500 dark:text-gray-400">
      Press Enter to send • Shift+Enter for new line
    </span>
  </div>
</div>

<style>
  .message-input-container {
    padding: 1rem 1.5rem;
    background: var(--color-panel);
    border-top: 1px solid var(--color-panel-border);
  }
  .input-wrapper { display: flex; align-items: flex-end; gap: 0.75rem; margin-bottom: 0.5rem; }
  .message-input { flex: 1; min-height: 2.5rem; max-height: 6rem; padding: 0.75rem 1rem; border: 1px solid var(--color-input-border); border-radius: 1.25rem; background: var(--color-input-bg); color: var(--color-text); font-size: 0.875rem; line-height: 1.4; resize: none; transition: all 0.2s ease; field-sizing: content; }
  .message-input:focus { outline: none; border-color: var(--color-bubble-self); box-shadow: 0 0 0 2px rgba(59, 130, 246, 0.2); }
  .message-input:disabled { opacity: 0.6; cursor: not-allowed; }

  .send-button { flex-shrink: 0; width: 2.5rem; height: 2.5rem; border: none; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-weight: 600; cursor: pointer; transition: all 0.2s ease; position: relative; }
  .send-button.enabled { background: var(--color-bubble-self); color: white; }
  .send-button.enabled:hover { background: var(--color-bubble-self-hover); }
  .send-button.enabled:active { transform: scale(0.95); }
  .send-button.disabled { background: #4a5568; color: #9ca3af; cursor: not-allowed; }

  .input-helper { display: flex; justify-content: center; }
  .input-helper span { color: var(--color-text-muted); }

  .loading-spinner { width: 16px; height: 16px; border: 2px solid #4a5568; border-top: 2px solid var(--color-bubble-self); border-radius: 50%; animation: spin 1s linear infinite; }
  .loading-spinner.small { width: 12px; height: 12px; border-width: 1.5px; }
  @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
</style>

