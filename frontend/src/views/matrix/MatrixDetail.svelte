<script lang="ts">
  import { onMount, onDestroy, tick } from 'svelte';
  import { MatrixViewModel } from '../../viewmodels/matrix/MatrixViewModel';
  import type { TimelineItem } from '../../models/shared/TimelineItem';
  import type { MatrixMessage } from '../../viewmodels/matrix/MatrixViewModel';
  import { writable, get } from 'svelte/store';

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
      // if VM supports tokens:
      (await matrixViewModel.loadOlderMessages(item.id, nextBatchToken)) ??
      (await matrixViewModel.loadOlderMessages(item.id));

    console.debug(
      `[MatrixDetail][loadMoreMessages] got ${olderMessages?.length || 0} older messages, new nextBatch=${nextBatch}`
    );

    if (olderMessages?.length) {
      messages.update((curr) => [...olderMessages, ...curr]);
    }
    nextBatchToken = nextBatch ?? null;

    await tick();
    if (messagesContainer) {
      const newScrollHeight = messagesContainer.scrollHeight;
      messagesContainer.scrollTop = prevScrollTop + (newScrollHeight - prevScrollHeight);
      console.debug(
        `[MatrixDetail][loadMoreMessages] Adjusted scrollTop to preserve viewport (prevTop=${prevScrollTop}, delta=${newScrollHeight - prevScrollHeight})`
      );
    }

    isLoadingOlderMessages = false;
  }

  // Reactive: fetch whenever switching rooms
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

  async function sendMessage() {
    if (!messageInput.trim() || !item?.id) {
      return;
    }
    const roomId = item.id;
    const content = messageInput;
    messageInput = ''; // Clear input immediately

    try {
      await matrixViewModel.sendMessage(roomId, content);
      // Optimistically add the message to the UI
      messages.update((curr) => [
        ...curr,
        {
          id: `temp-${Date.now()}`, // Temporary ID
          sender: matrixViewModel.getCurrentUserId(),
          description: content,
          timestamp: Date.now(),
          isSelf: true,
        },
      ]);
      await tick();
      messagesContainer.scrollTop = messagesContainer.scrollHeight;
    } catch (e) {
      console.error('[MatrixDetail][sendMessage] Failed to send message:', e);
      // Revert messageInput if sending failed, or show an error
      messageInput = content;
    }
  }
</script>

<div class="messages-container {className}" bind:this={messagesContainer}>
  <div bind:this={topSentinel} style="height:1px;"></div>

  {#if isLoadingOlderMessages}
    <div class="loading-indicator">Loading older messages...</div>
  {/if}

  {#if !nextBatchToken && $messages.length > 0}
    <div class="no-more-messages">No more older messages.</div>
  {/if}

  {#each $messages as m (m.id)}
    <div class="bubble {m.isSelf ? 'self' : 'other'}">
      <div class="body">{m.description}</div>
      <div class="meta">{new Date(m.timestamp).toLocaleString()}</div>
    </div>
  {/each}
</div>

<div class="message-input-container">
  <input
    type="text"
    placeholder="Type your message..."
    bind:value={messageInput}
    on:keydown={(e) => {
      if (e.key === 'Enter') sendMessage();
    }}
  />
  <button on:click={sendMessage} disabled={!messageInput.trim()}>Send</button>
</div>

<style>
  .messages-container {
    height: 100%;
    overflow-y: auto;
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 8px;
    flex-grow: 1; /* Allow it to grow and take available space */
  }

  .bubble {
    max-width: 92%;
    width: max-content;
    padding: 10px 12px;
    border-radius: 14px;
    background: #2a2a2a;
    color: #e5e7eb;
    box-sizing: border-box;
    line-height: 1.35;
    word-break: break-word;
  }
  .bubble.self {
    align-self: flex-end;
    background: #3b82f6;
    color: white;
  }
  .bubble.other {
    align-self: flex-start;
    background: #1f2937;
  }

  .body {
    white-space: pre-wrap;
  }
  .meta {
    font-size: 11px;
    opacity: 0.7;
    margin-top: 4px;
    text-align: right;
  }

  .loading-indicator,
  .no-more-messages {
    text-align: center;
    padding: 8px;
    color: gray;
    font-size: 13px;
  }

  .message-input-container {
    display: flex;
    padding: 8px;
    border-top: 1px solid #333;
    background-color: #1e1e1e;
    gap: 8px;
  }

  .message-input-container input {
    flex-grow: 1;
    padding: 10px;
    border-radius: 20px;
    border: 1px solid #555;
    background-color: #2a2a2a;
    color: #e5e7eb;
    font-size: 14px;
  }

  .message-input-container input:focus {
    outline: none;
    border-color: #3b82f6;
  }

  .message-input-container button {
    padding: 10px 15px;
    border-radius: 20px;
    border: none;
    background-color: #3b82f6;
    color: white;
    font-weight: bold;
    cursor: pointer;
    transition: background-color 0.2s;
  }

  .message-input-container button:hover:not(:disabled) {
    background-color: #2563eb;
  }

  .message-input-container button:disabled {
    background-color: #4a5568;
    cursor: not-allowed;
  }
</style>
