<!-- MatrixDetail.svelte -->
<script lang="ts">
  import { onMount, onDestroy, tick } from 'svelte';
  import { MatrixViewModel } from '../../viewmodels/matrix/MatrixViewModel';
  import type { TimelineItem } from '../../models/shared/TimelineItem';
  import { writable, get } from 'svelte/store';
  import type { MatrixMessage } from '@/viewmodels/matrix/MatrixTimelineService';

  export let item: TimelineItem;
  export let className: string = '';

  const matrixViewModel = MatrixViewModel.getInstance();

  const messages = writable<MatrixMessage[]>([]);
  let isLoadingOlderMessages = false;
  let nextBatchToken: string | null = null;

  let messagesContainer: HTMLDivElement;
  let topSentinel: HTMLDivElement;
  let scrollObserver: IntersectionObserver;

  async function fetchMessages(roomId: string) {
    try {
      console.debug(`[MatrixDetail][fetchMessages] Fetching initial messages for room=${roomId}`);
      const { messages: fetched, nextBatch } = await matrixViewModel.getRoomMessages(roomId, null);
      messages.set(fetched);
      nextBatchToken = nextBatch;
      console.debug(`[MatrixDetail][fetchMessages] got ${fetched.length}, next=${nextBatch}`);

      await tick();
      messagesContainer.scrollTop = messagesContainer.scrollHeight;
      await ensureScrollable();
    } catch (e) {
      console.debug(`[MatrixDetail][fetchMessages] ERROR:`, e);
    }
  }

  async function ensureScrollable() {
    let safety = 10;
    while (
      safety-- > 0 &&
      messagesContainer &&
      messagesContainer.scrollHeight <= messagesContainer.clientHeight &&
      nextBatchToken
    ) {
      console.debug(
        `[MatrixDetail][ensureScrollable] Container not scrollable yet (scrollHeight=${messagesContainer.scrollHeight}, clientHeight=${messagesContainer.clientHeight}), loading more...`
      );
      await loadMoreMessages();
      await tick();
    }
    console.debug(
      `[MatrixDetail][ensureScrollable] Done. scrollHeight=${messagesContainer?.scrollHeight}, clientHeight=${messagesContainer?.clientHeight}, nextBatchToken=${nextBatchToken}`
    );
  }

  async function loadMoreMessages() {
    if (isLoadingOlderMessages || !nextBatchToken) {
      console.debug(
        `[MatrixDetail][loadMoreMessages] Skipped: isLoadingOlderMessages=${isLoadingOlderMessages}, nextBatchToken=${nextBatchToken}`
      );
      return;
    }
    isLoadingOlderMessages = true;
    console.debug(
      `[MatrixDetail][loadMoreMessages] Loading older messages… currentCount=${get(messages).length}, nextBatch=${nextBatchToken}`
    );

    const prevScrollHeight = messagesContainer?.scrollHeight ?? 0;
    const prevScrollTop = messagesContainer?.scrollTop ?? 0;

    const { messages: olderMessages, nextBatch } =
      (await matrixViewModel.loadOlderMessages(item.id, nextBatchToken)) ??
      (await matrixViewModel.loadOlderMessages(item.id));

    console.debug(
      `[MatrixDetail][loadMoreMessages] got ${olderMessages?.length || 0} older messages, new nextBatch=${nextBatch}`
    );

    if (olderMessages?.length) {
      messages.update((curr) => {
        const existingIds = new Set(curr.map((m) => m.id));
        const newMessages = olderMessages.filter((m) => !existingIds.has(m.id));
        return [...newMessages, ...curr];
      });
    }
    nextBatchToken = nextBatch ?? null;

    await tick();
    if (messagesContainer) {
      // Temporarily disable smooth scroll behavior for instant jump
      messagesContainer.style.scrollBehavior = 'auto';
      const newScrollHeight = messagesContainer.scrollHeight;
      messagesContainer.scrollTop = prevScrollTop + (newScrollHeight - prevScrollHeight);
      console.debug(
        `[MatrixDetail][loadMoreMessages] Adjusted scrollTop to preserve viewport (prevTop=${prevScrollTop}, delta=${newScrollHeight - prevScrollHeight})`
      );
      // Re-enable smooth scroll behavior after adjustment
      await tick(); // Ensure the scroll adjustment has been applied
      messagesContainer.style.scrollBehavior = 'smooth';
    }

    isLoadingOlderMessages = false;
  }

  $: if (item?.type === 'matrix' && item.id) {
    console.debug(`[MatrixDetail][reactive] item changed -> fetching messages for room=${item.id}`);
    fetchMessages(item.id);
  }

  function setupObserver() {
    if (scrollObserver) scrollObserver.disconnect();

    scrollObserver = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting) {
          console.debug(
            '[MatrixDetail][IntersectionObserver] Top sentinel intersecting → loadMoreMessages()'
          );
          loadMoreMessages();
        }
      },
      {
        root: messagesContainer,
        threshold: 0.01,
        rootMargin: '0px 0px -90% 0px',
      }
    );

    if (topSentinel) {
      scrollObserver.observe(topSentinel);
      console.debug('[MatrixDetail][setupObserver] Observer attached to top sentinel');
    }
  }

  onMount(async () => {
    await tick();
    setupObserver();
    console.debug('[MatrixDetail][onMount] Component mounted');
  });

  onDestroy(() => {
    scrollObserver?.disconnect();
    console.debug('[MatrixDetail][onDestroy] Observer disconnected');
    if (item?.type === 'matrix' && item.id) {
      matrixViewModel.clearRoomPaginationTokens(item.id);
      console.debug(`[MatrixDetail][onDestroy] Cleared pagination tokens for room=${item.id}`);
    }
  });

  let messageInput: string = '';
  let isSending = false;

  async function sendMessage() {
    if (!messageInput.trim() || !item?.id || isSending) {
      return;
    }
    
    const roomId = item.id;
    const content = messageInput;
    messageInput = '';
    isSending = true;

    try {
      await matrixViewModel.sendMessage(roomId, content);
      messages.update((curr) => [
        ...curr,
        {
          id: `temp-${Date.now()}`,
          sender: matrixViewModel.getCurrentUserId(),
          senderDisplayName: matrixViewModel.getCurrentUserDisplayName(), // Add senderDisplayName
          description: content,
          timestamp: Date.now(),
          isSelf: true,
          msgtype: 'm.text',
        },
      ]);
      await tick();
      messagesContainer.scrollTop = messagesContainer.scrollHeight;
    } catch (e) {
      console.error('[MatrixDetail][sendMessage] Failed to send message:', e);
      messageInput = content;
    } finally {
      isSending = false;
    }
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      sendMessage();
    }
  }

  $: formattedRoomName = item.title || 'Matrix Room';
  $: canSend = messageInput.trim().length > 0 && !isSending;
</script>

<div class="matrix-detail-panel {className}">
  <!-- Enhanced Header -->
  <div class="room-header">
    <div class="flex items-center space-x-3">
      <!-- Room icon -->
      <div class="flex h-10 w-10 items-center justify-center rounded-xl bg-gradient-to-br from-emerald-500 to-teal-600 shadow-lg">
        <svg class="h-5 w-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
        </svg>
      </div>
      <div>
        <h2 class="text-lg font-semibold text-gray-900 dark:text-white">{formattedRoomName}</h2>
        <p class="text-sm text-gray-500 dark:text-gray-400">{$messages.length} messages</p>
      </div>
    </div>
    
    <!-- Room actions -->
    <div class="flex items-center space-x-2">
      <button class="rounded-lg p-2 text-gray-500 transition-colors hover:bg-gray-100 hover:text-gray-700 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-gray-300">
        <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
      </button>
    </div>
  </div>

  <!-- Messages Container -->
  <div class="messages-container" bind:this={messagesContainer}>
    <div bind:this={topSentinel} class="sentinel"></div>

    <!-- Loading indicator for older messages -->
    {#if isLoadingOlderMessages}
      <div class="loading-indicator">
        <div class="flex items-center justify-center space-x-2">
          <div class="loading-spinner"></div>
          <span>Loading older messages...</span>
        </div>
      </div>
    {/if}

    <!-- No more messages indicator -->
    {#if !nextBatchToken && $messages.length > 0}
      <div class="no-more-messages">
        <div class="flex items-center justify-center">
          <div class="rounded-full bg-gray-200 px-4 py-2 text-sm text-gray-600 dark:bg-gray-700 dark:text-gray-400">
            Beginning of conversation
          </div>
        </div>
      </div>
    {/if}

    <!-- Messages -->
    {#each $messages as message, index (message.id)}
      {@const isFirstInGroup = index === 0 || $messages[index - 1].sender !== message.sender}
      {@const isLastInGroup = index === $messages.length - 1 || $messages[index + 1].sender !== message.sender}
      
      <div class="message-wrapper {message.isSelf ? 'self' : 'other'}">
        <div class="message-bubble {message.isSelf ? 'self' : 'other'} {isFirstInGroup ? 'first-in-group' : ''} {isLastInGroup ? 'last-in-group' : ''}">
          <!-- Sender name (only for first message in group from others) -->
          {#if !message.isSelf && isFirstInGroup}
            <div class="sender-name">{message.senderDisplayName}</div>
          {/if}

          <!-- Message content -->
          {#if message.msgtype === 'm.image'}
            <div class="image-wrapper">
              {#if message.imageUrl}
                <img
                  src={message.imageUrl}
                  alt={message.description}
                  class="message-image"
                  referrerpolicy="no-referrer"
                  loading="lazy"
                />
              {:else}
                <div class="image-placeholder">
                  <div class="loading-spinner small"></div>
                  <span>Decrypting image…</span>
                </div>
              {/if}
            </div>
          {:else}
            <div class="message-content">{message.description}</div>
          {/if}
          
          <!-- Timestamp (only on last message in group) -->
          {#if isLastInGroup}
            <div class="message-timestamp">
              {new Date(message.timestamp).toLocaleTimeString('en-US', { 
                hour: '2-digit', 
                minute: '2-digit',
                hour12: false 
              })}
            </div>
          {/if}
        </div>
      </div>
    {/each}
  </div>

  <!-- Enhanced Message Input -->
  <div class="message-input-container">
    <div class="input-wrapper">
      <textarea
        bind:value={messageInput}
        on:keydown={handleKeydown}
        placeholder="Type your message... (Shift+Enter for new line)"
        class="message-input"
        rows="1"
        disabled={isSending}
      ></textarea>
      
      <button
        on:click={sendMessage}
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
    
    <!-- Input helper text -->
    <div class="input-helper">
      <span class="text-xs text-gray-500 dark:text-gray-400">
        Press Enter to send • Shift+Enter for new line
      </span>
    </div>
  </div>
</div>

<style>
  .matrix-detail-panel {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: var(--color-panel);
    color: var(--color-text);
  }

  .room-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 1rem 1.5rem;
    background: var(--color-panel);
    border-bottom: 1px solid var(--color-panel-border);
    position: sticky;
    top: 0;
    z-index: 10;
  }

  .messages-container {
    flex: 1;
    overflow-y: auto;
    padding: 1rem;
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
    /* Temporarily remove scroll-behavior: smooth from here */
    background: var(--color-panel);
  }

  .sentinel {
    height: 1px;
    opacity: 0;
  }

  .loading-indicator,
  .no-more-messages {
    display: flex;
    justify-content: center;
    padding: 1rem 0;
    margin: 0.5rem 0;
    color: var(--color-text-muted);
  }

  .loading-spinner {
    width: 16px;
    height: 16px;
    border: 2px solid #4a5568;
    border-top: 2px solid var(--color-bubble-self);
    border-radius: 50%;
    animation: spin 1s linear infinite;
  }
  
  .loading-spinner.small {
    width: 12px;
    height: 12px;
    border-width: 1.5px;
  }

  @keyframes spin {
    0% { transform: rotate(0deg); }
    100% { transform: rotate(360deg); }
  }

  .message-wrapper {
    display: flex;
    margin-bottom: 2px;
  }
  
  .message-wrapper.self {
    justify-content: flex-end;
  }
  
  .message-wrapper.other {
    justify-content: flex-start;
  }

  .message-bubble {
    max-width: 75%;
    padding: 0.75rem 1rem;
    border-radius: 1rem;
    background: var(--color-input-bg);
    color: var(--color-text);
    position: relative;
    word-break: break-word;
    transition: all 0.2s ease;
    line-height: 1.35;
  }
  
  .message-bubble:hover { background: var(--color-bubble-other-hover); }

  .message-bubble.self { background: var(--color-bubble-self); color: white; margin-left: auto; }
  
  .message-bubble.self:hover { background: var(--color-bubble-self-hover); }

  .message-bubble.other { background: var(--color-bubble-other); color: var(--color-text); }
  
  .message-bubble.other:hover { background: var(--color-bubble-other-hover); }

  /* Bubble grouping styles */
  .message-bubble.first-in-group.other {
    border-top-left-radius: 1rem;
  }
  
  .message-bubble.first-in-group.self {
    border-top-right-radius: 1rem;
  }
  
  .message-bubble.last-in-group.other {
    border-bottom-left-radius: 1rem;
    margin-bottom: 0.75rem;
  }
  
  .message-bubble.last-in-group.self {
    border-bottom-right-radius: 1rem;
    margin-bottom: 0.75rem;
  }
  
  .message-bubble:not(.first-in-group):not(.last-in-group).other {
    border-top-left-radius: 0.25rem;
    border-bottom-left-radius: 0.25rem;
  }
  
  .message-bubble:not(.first-in-group):not(.last-in-group).self {
    border-top-right-radius: 0.25rem;
    border-bottom-right-radius: 0.25rem;
  }

  .sender-name {
    font-size: 0.75rem;
    font-weight: 600;
    color: #60a5fa;
    margin-bottom: 0.25rem;
  }

  .message-content {
    white-space: pre-wrap;
    line-height: 1.4;
  }

  .message-image {
    max-width: 100%;
    max-height: 100%;
    object-fit: contain;
    display: block;
    border-radius: 0.5rem;
  }

  /* Image container with size limits */
  .image-wrapper {
    max-width: 360px;
    max-height: 360px;
    width: 100%;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    overflow: hidden;
    border-radius: 0.5rem;
    background: var(--color-input-bg);
  }

  .image-placeholder {
    min-width: 180px;
    min-height: 140px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 0.5rem;
    color: var(--color-text-muted);
  }

  .message-timestamp {
    font-size: 0.65rem;
    opacity: 0.7;
    margin-top: 0.25rem;
    text-align: right;
  }

  .message-input-container {
    padding: 1rem 1.5rem;
    background: var(--color-panel);
    border-top: 1px solid var(--color-panel-border);
  }

  .input-wrapper {
    display: flex;
    align-items: flex-end;
    gap: 0.75rem;
    margin-bottom: 0.5rem;
  }

  .message-input {
    flex: 1;
    min-height: 2.5rem;
    max-height: 6rem;
    padding: 0.75rem 1rem;
    border: 1px solid var(--color-input-border);
    border-radius: 1.25rem;
    background: var(--color-input-bg);
    color: var(--color-text);
    font-size: 0.875rem;
    line-height: 1.4;
    resize: none;
    transition: all 0.2s ease;
  }
  
  .message-input:focus {
    outline: none;
    border-color: var(--color-bubble-self);
    box-shadow: 0 0 0 2px rgba(59, 130, 246, 0.2);
  }
  
  .message-input:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .send-button {
    flex-shrink: 0;
    width: 2.5rem;
    height: 2.5rem;
    border: none;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.2s ease;
    position: relative;
  }

  .send-button.enabled { background: var(--color-bubble-self); color: white; }

  .send-button.enabled:hover { background: var(--color-bubble-self-hover); }

  .send-button.enabled:active {
    transform: scale(0.95);
  }

  .send-button.disabled {
    background: #4a5568;
    color: #9ca3af;
    cursor: not-allowed;
  }

  .input-helper {
    display: flex;
    justify-content: center;
  }

  .input-helper span { color: var(--color-text-muted); }

  /* Auto-resize textarea */
  .message-input {
    field-sizing: content;
  }
</style>
