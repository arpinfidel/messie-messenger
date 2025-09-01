<!-- MatrixDetail.svelte -->
<script lang="ts">
  import { onMount, onDestroy, tick } from 'svelte';
  import { MatrixViewModel } from '../../viewmodels/matrix/MatrixViewModel';
  import type { TimelineItem } from '../../models/shared/TimelineItem';
  import { writable, get } from 'svelte/store';
  import type { MatrixMessage } from '@/viewmodels/matrix/MatrixTimelineService';
  import RoomHeader from './components/RoomHeader.svelte';
  import MessageItem from './components/MessageItem.svelte';
  import MessageInput from './components/MessageInput.svelte';

  export let item: TimelineItem;
  export let className: string = '';

  const matrixViewModel = MatrixViewModel.getInstance();

  const messages = writable<MatrixMessage[]>([]);
  let isLoadingOlderMessages = false;
  let nextBatch: number | null = null;

  let messagesContainer: HTMLDivElement;
  let topSentinel: HTMLDivElement;
  let scrollObserver: IntersectionObserver;

  async function fetchMessages(roomId: string) {
    try {
      console.debug(`[MatrixDetail][fetchMessages] Fetching initial messages for room=${roomId}`);
      const { messages: fetched, nextBatch: newNextBatch } = await matrixViewModel.getRoomMessages(roomId, null);
      messages.set(fetched);
      nextBatch = newNextBatch;
      console.debug(`[MatrixDetail][fetchMessages] got ${fetched.length}, next=${newNextBatch}`);

      await tick();
      messagesContainer.scrollTop = messagesContainer.scrollHeight;
      await ensureScrollable();
    } catch (e) {
      console.debug(`[MatrixDetail][fetchMessages] ERROR:`, e);
    }
  }

  onDestroy(() => {
    // Release any blob URLs held by the media cache to avoid memory leaks
    try { matrixViewModel.clearMediaCache(); } catch {}
  });

  async function ensureScrollable() {
    let safety = 10;
    while (
      safety-- > 0 &&
      messagesContainer &&
      messagesContainer.scrollHeight <= messagesContainer.clientHeight &&
      nextBatch
    ) {
      console.debug(
        `[MatrixDetail][ensureScrollable] Container not scrollable yet (scrollHeight=${messagesContainer.scrollHeight}, clientHeight=${messagesContainer.clientHeight}), loading more...`
      );
      await loadMoreMessages();
      await tick();
    }
    console.debug(
      `[MatrixDetail][ensureScrollable] Done. scrollHeight=${messagesContainer?.scrollHeight}, clientHeight=${messagesContainer?.clientHeight}, nextBatchToken=${nextBatch}`
    );
  }

  async function loadMoreMessages() {
    console.time(`[MatrixDetail][loadMoreMessages] room=${item?.id}`);
    if (isLoadingOlderMessages || !nextBatch) {
      console.debug(
        `[MatrixDetail][loadMoreMessages] Skipped: isLoadingOlderMessages=${isLoadingOlderMessages}, nextBatchToken=${nextBatch}`
      );
      return;
    }
    isLoadingOlderMessages = true;
    console.debug(
      `[MatrixDetail][loadMoreMessages] Loading older messages… currentCount=${get(messages).length}, nextBatch=${nextBatch}`
    );

    const prevScrollHeight = messagesContainer?.scrollHeight ?? 0;
    const prevScrollTop = messagesContainer?.scrollTop ?? 0;

    const { messages: olderMessages, nextBatch: newNextBatch } = await matrixViewModel.getRoomMessages(item.id, nextBatch);

    console.debug(
      `[MatrixDetail][loadMoreMessages] got ${olderMessages?.length || 0} older messages, new nextBatch=${newNextBatch}`
    );

    if (olderMessages?.length) {
      messages.update((curr) => {
        const existingIds = new Set(curr.map((m) => m.id));
        const newMessages = olderMessages.filter((m) => !existingIds.has(m.id));
        return [...newMessages, ...curr];
      });
    }
    nextBatch = newNextBatch;

    // await tick();
    if (messagesContainer) {
      // Temporarily disable smooth scroll behavior for instant jump
      messagesContainer.style.scrollBehavior = 'auto';
      const newScrollHeight = messagesContainer.scrollHeight;
      messagesContainer.scrollTop = prevScrollTop + (newScrollHeight - prevScrollHeight - 50);
      console.debug(
        `[MatrixDetail][loadMoreMessages] Adjusted scrollTop to preserve viewport (prevTop=${prevScrollTop}, delta=${newScrollHeight - prevScrollHeight})`
      );
      // Re-enable smooth scroll behavior after adjustment
      // await tick(); // Ensure the scroll adjustment has been applied
      messagesContainer.style.scrollBehavior = 'smooth';
    }

    isLoadingOlderMessages = false;
    console.timeEnd(`[MatrixDetail][loadMoreMessages] room=${item?.id}`);
  }

  $: if (item?.type === 'matrix' && item.id) {
    console.time(`[MatrixDetail][fetchMessages] room=${item.id}`);
    fetchMessages(item.id);
    console.timeEnd(`[MatrixDetail][fetchMessages] room=${item.id}`);
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
        rootMargin: '600px 0px -90% 0px', 
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

  let isSending = false;

  async function sendMessage(content: string) {
    if (!content.trim() || !item?.id || isSending) {
      return;
    }

    const roomId = item.id;
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
      // Let the input component keep the text if sending fails
    } finally {
      isSending = false;
    }
  }

  $: formattedRoomName = item.title || 'Matrix Room';
</script>

<div class="matrix-detail-panel {className}">
  <RoomHeader title={formattedRoomName} messageCount={$messages.length} roomId={item.id} />

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
    {#if !nextBatch && $messages.length > 0}
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
      <MessageItem {message} {isFirstInGroup} {isLastInGroup} />
    {/each}
  </div>

  <MessageInput {isSending} on:send={(e) => sendMessage(e.detail)} />
</div>

<style>
  .matrix-detail-panel {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: var(--color-panel);
    color: var(--color-text);
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


</style>
