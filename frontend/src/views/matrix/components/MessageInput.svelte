<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  import { Paperclip, Send, SendHorizonal, SendHorizontal } from 'lucide-svelte';
  import type { MatrixReplyContext } from '@/viewmodels/matrix/types';

  export let isSending: boolean = false;
  export let className: string = '';
  export let hasAttachment: boolean = false;
  export let replyTo: MatrixReplyContext | null = null;

  import PopupMenu from '@/views/shared/PopupMenu.svelte';

  const dispatch = createEventDispatcher<{
    send: { content: string; replyTo: MatrixReplyContext | null };
    sendMedia: void;
    sendFile: void;
    cancelReply: void;
  }>();

  let text = '';
  let textareaEl: HTMLTextAreaElement;
  let canSend: boolean;
  $: canSend = (text.trim().length > 0 || hasAttachment) && !isSending;

  let showMenu = false;
  let attachButton: HTMLButtonElement;

  function handleAttachClick() {
    if (isSending) return;
    showMenu = !showMenu;
  }

  function pickMedia() {
    showMenu = false;
    dispatch('sendMedia');
  }

  function pickFile() {
    showMenu = false;
    dispatch('sendFile');
  }

  function describeMsgtype(msgtype?: string): string {
    switch (msgtype) {
      case 'm.image':
        return 'Image';
      case 'm.video':
        return 'Video';
      case 'm.audio':
        return 'Audio';
      case 'm.file':
        return 'File';
      default:
        return 'Message';
    }
  }

  function getReplyAuthor(context: MatrixReplyContext | null): string {
    if (!context) return '';
    return (
      context.senderDisplayName?.trim() ||
      context.sender?.trim() ||
      context.fallbackSender?.trim() ||
      'Unknown user'
    );
  }

  function truncate(value: string, max = 140): string {
    if (value.length <= max) return value;
    return `${value.slice(0, max - 1)}…`;
  }

  function getReplySnippet(context: MatrixReplyContext | null): string {
    if (!context) return '';
    const source =
      context.body?.trim() ||
      context.fallbackBody?.trim() ||
      describeMsgtype(context.msgtype);
    if (!source) return '';
    return truncate(source.replace(/\s+/g, ' ').trim());
  }

  function trySend() {
    const content = text.trim();
    if ((!content && !hasAttachment) || isSending) return;
    dispatch('send', { content, replyTo });
    text = '';
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      trySend();
    }
  }

  // Expose focus method to parent components
  export function focus() {
    if (textareaEl) {
      textareaEl.focus();
      // place cursor at end
      const len = textareaEl.value.length;
      try {
        textareaEl.setSelectionRange(len, len);
      } catch (err) {
        console.warn('[MessageInput] setSelectionRange failed', err);
      }
    }
  }
</script>

  <div class="message-input-container {className}">
    {#if replyTo}
      <div class="reply-banner">
        <div class="reply-text">
          <span class="reply-label">Replying to {getReplyAuthor(replyTo)}</span>
          <span class="reply-snippet">{getReplySnippet(replyTo)}</span>
        </div>
        <button
          class="reply-cancel"
          type="button"
          aria-label="Cancel reply"
          on:click={() => dispatch('cancelReply')}
        >
          ×
        </button>
      </div>
    {/if}
    <div class="input-wrapper">
    <button
      bind:this={attachButton}
      on:click={handleAttachClick}
      class="media-button"
      title="Attach"
      disabled={isSending}
    >
      <Paperclip class="h-5 w-5"  aria-hidden="true" />
    </button>
    <PopupMenu anchor={attachButton} show={showMenu} on:close={() => (showMenu = false)}>
      <div class="flex flex-col">
        <button
          class="rounded px-4 py-2 text-left text-sm hover:bg-gray-100 dark:hover:bg-gray-700"
          on:click={pickMedia}
        >
          Image / Video
        </button>
        <button
          class="rounded px-4 py-2 text-left text-sm hover:bg-gray-100 dark:hover:bg-gray-700"
          on:click={pickFile}
        >
          File
        </button>
      </div>
    </PopupMenu>
    <textarea
      bind:this={textareaEl}
      bind:value={text}
      on:keydown={handleKeydown}
      placeholder="Type your message"
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
        <SendHorizontal class="h-5 w-5" aria-hidden="true" />
      {/if}
    </button>
  </div>
</div>

<style>
  .message-input-container {
    padding: 0.5rem 1rem;
    /* background: var(--color-panel); */
    /* background: rgba(0,0,0,0); */
    /* border-top: 1px solid var(--color-panel-border); */
  }
  .reply-banner {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.75rem;
    padding: 0.5rem 0.75rem;
    margin-bottom: 0.5rem;
    border-radius: 0.75rem;
    background: var(--color-input-bg);
    border-left: 3px solid var(--color-bubble-self);
  }
  .reply-text {
    display: flex;
    flex-direction: column;
    gap: 0.15rem;
    min-width: 0;
    font-size: 0.75rem;
  }
  .reply-label {
    font-weight: 600;
    color: var(--color-text);
  }
  .reply-snippet {
    color: var(--color-text-muted);
    font-size: 0.75rem;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    max-width: 28ch;
  }
  .reply-cancel {
    flex-shrink: 0;
    width: 1.75rem;
    height: 1.75rem;
    border-radius: 9999px;
    border: none;
    background: transparent;
    color: var(--color-text);
    display: inline-flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    font-size: 1.1rem;
    transition: background 0.15s ease, color 0.15s ease;
  }
  .reply-cancel:hover,
  .reply-cancel:focus-visible {
    background: rgba(255,255,255,0.1);
    color: var(--color-text);
    outline: none;
  }
  .input-wrapper { display: flex; align-items: flex-end; gap: 0.75rem; }
  .message-input { flex: 1; min-height: 2.5rem; max-height: 6rem; padding: 0.75rem 1rem; border: 1px solid var(--color-input-border); border-radius: 1.25rem; background: var(--color-input-bg); color: var(--color-text); font-size: 0.875rem; line-height: 1.4; resize: none; transition: all 0.2s ease; field-sizing: content; }
  .message-input:focus { outline: none; border-color: var(--color-bubble-self); box-shadow: 0 0 0 2px rgba(59, 130, 246, 0.2); }
  .message-input:disabled { opacity: 0.6; cursor: not-allowed; }

  .send-button { flex-shrink: 0; width: 2.5rem; height: 2.5rem; border: none; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-weight: 600; cursor: pointer; transition: all 0.2s ease; position: relative; }
  .send-button.enabled { background: var(--color-bubble-self); color: white; }
  .send-button.enabled:hover { background: var(--color-bubble-self-hover); }
  .send-button.enabled:active { transform: scale(0.95); }
  .send-button.disabled { background: #4a5568; color: #9ca3af; cursor: not-allowed; }

  .media-button {
    flex-shrink: 0;
    width: 2.5rem;
    height: 2.5rem;
    border: none;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    background: #4a5568;
    color: #9ca3af;
    cursor: pointer;
    transition: all 0.2s ease;
  }
  .media-button:hover { background: #5a6679; }
  .media-button:disabled { opacity: 0.6; cursor: not-allowed; }

  .loading-spinner { width: 16px; height: 16px; border: 2px solid #4a5568; border-top: 2px solid var(--color-bubble-self); border-radius: 50%; animation: spin 1s linear infinite; }
  .loading-spinner.small { width: 12px; height: 12px; border-width: 1.5px; }
  @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
</style>
