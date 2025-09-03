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

  // Jump-to-bottom state
  let showJumpToBottom = false;
  let unreadCount = 0;

  function isNearBottom(el: HTMLDivElement | undefined, threshold = 100) {
    if (!el) return true;
    return el.scrollTop + el.clientHeight >= el.scrollHeight - threshold;
  }

  function updateJumpVisibility() {
    if (!messagesContainer) return;
    const near = isNearBottom(messagesContainer);
    showJumpToBottom = !near;
    if (near) unreadCount = 0;
  }

  async function scrollToBottom() {
    if (!messagesContainer) return;
    const prev = messagesContainer.style.scrollBehavior;
    messagesContainer.style.scrollBehavior = 'smooth';
    messagesContainer.scrollTop = messagesContainer.scrollHeight;
    // restore after the smooth scroll
    setTimeout(() => {
      if (messagesContainer) messagesContainer.style.scrollBehavior = prev;
      updateJumpVisibility();
    }, 200);
  }

  let messagesContainer: HTMLDivElement;
  let topSentinel: HTMLDivElement;
  let scrollObserver: IntersectionObserver;
  let unsubscribeRepoEvent: (() => void) | null = null;
  let onScroll: (() => void) | undefined;

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

    // Store scroll position relative to the bottom before loading
    const prevScrollHeight = messagesContainer?.scrollHeight ?? 0;
    const prevScrollTop = messagesContainer?.scrollTop ?? 0;
    const distanceFromBottom = prevScrollHeight - prevScrollTop - messagesContainer.clientHeight;

    try {
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

        // Wait for DOM to update
        await tick();
        
        if (messagesContainer) {
          // Disable smooth scrolling temporarily
          const originalScrollBehavior = messagesContainer.style.scrollBehavior;
          messagesContainer.style.scrollBehavior = 'auto';
          
          // Calculate new scroll position to maintain the same distance from bottom
          const newScrollHeight = messagesContainer.scrollHeight;
          const newScrollTop = newScrollHeight - messagesContainer.clientHeight - distanceFromBottom;
          
          console.debug(
            `[MatrixDetail][loadMoreMessages] Scroll adjustment: prevHeight=${prevScrollHeight}, newHeight=${newScrollHeight}, distanceFromBottom=${distanceFromBottom}, newScrollTop=${newScrollTop}`
          );
          
          // Set the new scroll position
          messagesContainer.scrollTop = Math.max(0, newScrollTop);
          
          // Restore original scroll behavior
          messagesContainer.style.scrollBehavior = originalScrollBehavior;
        }
      }

      nextBatch = newNextBatch;
    } catch (error) {
      console.error(`[MatrixDetail][loadMoreMessages] Error loading messages:`, error);
    } finally {
      isLoadingOlderMessages = false;
      console.timeEnd(`[MatrixDetail][loadMoreMessages] room=${item?.id}`);
    }
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
        if (entries[0].isIntersecting && !isLoadingOlderMessages) {
          console.debug(
            '[MatrixDetail][IntersectionObserver] Top sentinel intersecting → loadMoreMessages()'
          );
          loadMoreMessages();
        }
      },
      {
        root: messagesContainer,
        threshold: 1.0,
        rootMargin: '500px 0px -70% 0px', // Increased from 200px to 500px for earlier loading
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

    onScroll = () => updateJumpVisibility();
    messagesContainer?.addEventListener('scroll', onScroll, { passive: true });

    // Replace the current unsubscribeRepoEvent assignment with this enhanced handler:
    unsubscribeRepoEvent = matrixViewModel.onRepoEvent(async (ev, _room) => {
      if (ev.roomId !== item.id) return;
      const newMsgs = await matrixViewModel.mapRepoEventsToMessages([ev]);
      if (!newMsgs.length) return;

      const wasNear = isNearBottom(messagesContainer);
      messages.update((curr) => {
        const existing = new Set(curr.map((m) => m.id));
        const toAdd = newMsgs.filter((m) => !existing.has(m.id));
        return toAdd.length ? [...curr, ...toAdd] : curr;
      });

      await tick();

      if (wasNear) {
        messagesContainer.scrollTop = messagesContainer.scrollHeight;
        unreadCount = 0;
        showJumpToBottom = false;
      } else {
        unreadCount += newMsgs.length;
        showJumpToBottom = true;
      }
    });

    // Initial compute
    updateJumpVisibility();
    console.debug('[MatrixDetail][onMount] Component mounted');
  });

  onDestroy(() => {
    scrollObserver?.disconnect();
    unsubscribeRepoEvent?.();
    messagesContainer?.removeEventListener('scroll', onScroll as any);
    console.debug('[MatrixDetail][onDestroy] Observer disconnected');
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
          senderDisplayName: matrixViewModel.getCurrentUserDisplayName(),
          description: content,
          timestamp: Date.now(),
          isSelf: true,
          msgtype: 'm.text',
        },
      ]);
      await tick();
      messagesContainer.scrollTop = messagesContainer.scrollHeight;
      unreadCount = 0;
      showJumpToBottom = false;
    } catch (e) {
      console.error('[MatrixDetail][sendMessage] Failed to send message:', e);
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

    {#if showJumpToBottom}
      <div class="jump-to-bottom-wrap">
        <button class="jump-to-bottom" on:click={scrollToBottom} aria-label="Jump to latest">
          <svg viewBox="0 0 24 24" class="icon" aria-hidden="true">
            <path d="M12 16l-6-6h12l-6 6z"></path>
          </svg>
          {#if unreadCount > 0}
            <span class="badge">{unreadCount > 99 ? '99+' : unreadCount}</span>
          {/if}
        </button>
      </div>
    {/if}
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
    position: relative;
    flex: 1;
    overflow-y: auto;
    padding: 1rem;
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
    background: var(--color-panel);
    scroll-behavior: smooth;
    padding-bottom: 0.5rem; /* Optional: tiny bottom padding so the last message isn't flush with the sticky bar */
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
  /* Sticky wrapper: sticks the button to the bottom edge of the scroll area */
  .jump-to-bottom-wrap {
    position: sticky;
    bottom: 0;               /* stick to bottom of the messages container */
    display: flex;
    justify-content: flex-end;
    pointer-events: none;    /* let clicks pass through except on the button */
    /* Add a subtle fade to separate from messages */
    background: linear-gradient(
      to top,
      color-mix(in srgb, var(--color-panel) 92%, transparent),
      transparent 70%
    );
    padding: 0.5rem 0.25rem 0.25rem 0.25rem; /* small breathing room */
    margin-top: 0.25rem;
  }

  /* The actual button is clickable */
  .jump-to-bottom {
    pointer-events: auto;
    display: inline-flex;
    align-items: center;
    gap: 0.5rem;
    border: none;
    border-radius: 9999px;
    padding: 0.5rem 0.75rem;
    background: linear-gradient(135deg, var(--color-bubble-self), var(--color-accent, #4f46e5));
    color: #fff;
    box-shadow: 0 8px 20px rgba(0,0,0,0.25);
    cursor: pointer;
    opacity: 0.95;
    transition: transform 120ms ease, opacity 120ms ease;
  }

  .jump-to-bottom:hover { transform: translateY(-1px); opacity: 1; }
  .jump-to-bottom:active { transform: translateY(0); }

  .jump-to-bottom .icon {
    width: 20px; height: 20px;
    fill: currentColor;
  }

  .jump-to-bottom .badge {
    min-width: 1.5rem;
    height: 1.25rem;
    padding: 0 0.375rem;
    border-radius: 9999px;
    font-size: 0.75rem;
    line-height: 1.25rem;
    text-align: center;
    background: rgba(255,255,255,0.2);
    color: #fff;
    backdrop-filter: saturate(180%) blur(6px);
  }
</style>