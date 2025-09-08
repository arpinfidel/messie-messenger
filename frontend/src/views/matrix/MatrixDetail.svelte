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

  const scrollThreshold = 0.25;

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
    if (near) {
      unreadCount = 0;
      if (item?.id) {
        matrixViewModel.markRoomAsRead(item.id);
      }
    }
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
  let messageInputRef: any;
  let unsubscribeRepoEvent: (() => void) | null = null;
  let unsubscribeReceipt: (() => void) | null = null;
  let scrollHandler: (() => void) | null = null;
  let onScroll: (() => void) | undefined;
  // Max read timestamp among other members; used to render status
  let minOtherReadTs = 0;

  async function refreshMinReadTs() {
    if (!item?.id) return;
    minOtherReadTs = await matrixViewModel.getMinOtherReadTs(item.id);
  }

  // Image lightbox state
  let lightboxUrl: string | null = null;
  let lightboxDesc: string | undefined;
  // Media version for async avatar/image updates
  let mediaVersion = 0;

  function openLightbox(e: CustomEvent<{ url: string; description?: string }>) {
    lightboxUrl = e.detail.url;
    lightboxDesc = e.detail.description;
  }

  function closeLightbox() {
    lightboxUrl = null;
    lightboxDesc = undefined;
  }

  async function fetchMessages(roomId: string) {
    try {
      console.debug(`[MatrixDetail][fetchMessages] Fetching initial messages for room=${roomId}`);
      const { messages: fetched, nextBatch: newNextBatch } = await matrixViewModel.getRoomMessages(
        roomId,
        null
      );
      messages.set(fetched);
      nextBatch = newNextBatch;
      console.debug(`[MatrixDetail][fetchMessages] got ${fetched.length}, next=${newNextBatch}`);

      await tick();
      // Ensure we scroll to the very bottom without smooth scrolling on initial load
      if (messagesContainer) {
        messagesContainer.style.scrollBehavior = 'auto';
        messagesContainer.scrollTop = messagesContainer.scrollHeight;
        messagesContainer.style.scrollBehavior = 'smooth';
      }
      await ensureScrollable();
      updateJumpVisibility();
      matrixViewModel.markRoomAsRead(roomId);

      // After messages load and DOM settles, focus the message input
      await tick();
      messageInputRef?.focus();
    } catch (e) {
      console.debug(`[MatrixDetail][fetchMessages] ERROR:`, e);
    }
  }

  onDestroy(() => {
    // Release any blob URLs held by the media cache to avoid memory leaks
    matrixViewModel.clearMediaCache();
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

    // Store scroll position before loading
    const prevScrollHeight = messagesContainer?.scrollHeight ?? 0;
    const prevScrollTop = messagesContainer?.scrollTop ?? 0;

    try {
      const { messages: olderMessages, nextBatch: newNextBatch } =
        await matrixViewModel.getRoomMessages(item.id, nextBatch);

      console.debug(
        `[MatrixDetail][loadMoreMessages] got ${olderMessages?.length || 0} older messages, new nextBatch=${newNextBatch}`
      );

      let actualNewMessages = 0;
      if (olderMessages?.length) {
        messages.update((curr) => {
          const existingIds = new Set(curr.map((m) => m.id));
          const newMessages = olderMessages.filter((m) => !existingIds.has(m.id));
          actualNewMessages = newMessages.length;
          return [...newMessages, ...curr];
        });

        // Wait for DOM to update
        await tick();

        // Only adjust scroll if we actually got NEW messages (not duplicates)
        if (actualNewMessages > 0 && messagesContainer) {
          console.debug(
            `[MatrixDetail][loadMoreMessages] Got ${actualNewMessages} new messages, adjusting scroll`
          );

          // Disable smooth scrolling temporarily
          const originalScrollBehavior = messagesContainer.style.scrollBehavior;
          messagesContainer.style.scrollBehavior = 'auto';

          // Use height delta approach for more precise positioning
          const newScrollHeight = messagesContainer.scrollHeight;
          const heightDelta = newScrollHeight - prevScrollHeight;
          const newScrollTop = prevScrollTop + heightDelta;

          console.debug(
            `[MatrixDetail][loadMoreMessages] Height delta adjustment: prevHeight=${prevScrollHeight}, newHeight=${newScrollHeight}, heightDelta=${heightDelta}, newScrollTop=${newScrollTop}`
          );

          // Set the new scroll position
          messagesContainer.scrollTop = Math.max(0, newScrollTop);

          // Restore original scroll behavior
          messagesContainer.style.scrollBehavior = originalScrollBehavior;
        } else if (actualNewMessages === 0) {
          console.debug(
            `[MatrixDetail][loadMoreMessages] No new messages added (duplicates filtered), keeping scroll position unchanged`
          );
        }
      } else {
        console.debug(
          `[MatrixDetail][loadMoreMessages] No messages returned from API, keeping scroll position unchanged`
        );
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

  function setupScrollHandler() {
    if (scrollHandler) {
      messagesContainer?.removeEventListener('scroll', scrollHandler);
    }

    scrollHandler = () => {
      // Update jump-to-bottom visibility
      updateJumpVisibility();

      // Don't trigger loading if already loading or no more messages
      if (isLoadingOlderMessages || !nextBatch || !messagesContainer) return;

      const { scrollTop, scrollHeight, clientHeight } = messagesContainer;
      const scrollPercentage = scrollTop / Math.max(1, scrollHeight - clientHeight);

      if (scrollPercentage < scrollThreshold) {
        console.debug(
          `[MatrixDetail][ScrollHandler] Near top (${(scrollPercentage * 100).toFixed(1)}%) → loadMoreMessages()`
        );
        loadMoreMessages();
      }
    };

    if (messagesContainer) {
      messagesContainer.addEventListener('scroll', scrollHandler, { passive: true });
      console.debug('[MatrixDetail][setupScrollHandler] Scroll handler attached');
    }
  }

  // Subscribe immediately so early media bumps are not missed
  const unsubMedia = matrixViewModel.getMediaVersion().subscribe((v) => {
    mediaVersion = v;
  });

  onMount(async () => {
    await tick();
    setupScrollHandler();

    // Ensure input is focused on mount
    await tick();
    messageInputRef?.focus();

    // Replace the current unsubscribeRepoEvent assignment with this enhanced handler:
    unsubscribeRepoEvent = matrixViewModel.onRepoEvent(async (ev, _room, _meta) => {
      if (ev.roomId !== item.id) return;
      const newMsgs = await matrixViewModel.mapRepoEventsToMessages([ev]);
      if (!newMsgs.length) return;

      const wasNear = isNearBottom(messagesContainer);
      let newMessagesAtEnd = 0;

      messages.update((curr) => {
        // Create a working copy
        let result = [...curr];

        newMsgs.forEach((newMsg) => {
          // Check if message already exists (for updates)
          const existingIndex = result.findIndex((m) => m.id === newMsg.id);

          if (existingIndex !== -1) {
            // Update existing message in place
            result[existingIndex] = newMsg;
          } else {
            // Find the correct position to insert based on timestamp
            let low = 0;
            let high = result.length - 1;
            let insertIndex = result.length; // Default to end if newMsg is the newest

            // Use binary search to find the correct position to insert based on timestamp
            while (low <= high) {
              const mid = Math.floor((low + high) / 2);
              if (newMsg.timestamp < result[mid].timestamp) {
                insertIndex = mid;
                high = mid - 1;
              } else {
                low = mid + 1;
              }
            }

            // Insert at the correct position
            result.splice(insertIndex, 0, newMsg);

            // Track if this is a new message at the end (for unread count)
            if (insertIndex === result.length - 1) {
              newMessagesAtEnd++;
            }
          }
        });

        return result;
      });

      await tick();

      // Only auto-scroll if user was near bottom AND the new message(s) are at the end
      if (wasNear && newMessagesAtEnd > 0) {
        messagesContainer.scrollTop = messagesContainer.scrollHeight;
        unreadCount = 0;
        showJumpToBottom = false;
      } else if (newMessagesAtEnd > 0) {
        // Only increment unread count for new messages that appear at the end
        unreadCount += newMessagesAtEnd;
        showJumpToBottom = true;
      }
      // If messages were inserted in the middle (older messages), don't change scroll or unread count
    });

    // On receipt, recompute the max read timestamp once for this room
    unsubscribeReceipt = matrixViewModel.onReadReceipt((roomId) => {
      if (roomId !== item.id) return;
      refreshMinReadTs();
    });

    // Initial compute
    updateJumpVisibility();
    matrixViewModel.syncRoom(item.id).then(() => {
      refreshMinReadTs();
    });
    console.debug('[MatrixDetail][onMount] Component mounted');

    // Close lightbox on Escape
    const onKey = (ev: KeyboardEvent) => {
      if (ev.key === 'Escape' && lightboxUrl) {
        closeLightbox();
      }
    };
    window.addEventListener('keydown', onKey);
    onDestroy(() => window.removeEventListener('keydown', onKey));

    onDestroy(() => unsubMedia());
  });

  onDestroy(() => {
    if (scrollHandler && messagesContainer) {
      messagesContainer.removeEventListener('scroll', scrollHandler);
    }
    unsubscribeRepoEvent?.();
    unsubscribeReceipt?.();
    console.debug('[MatrixDetail][onDestroy] Scroll handler removed');
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
    } catch (e) {
      console.error('[MatrixDetail][sendMessage] Failed to send message:', e);
    } finally {
      isSending = false;
      // Keep focus on the message input after sending
      await tick();
      messageInputRef?.focus();
    }
  }

  async function sendMedia() {
    if (!item?.id || isSending) return;
    const roomId = item.id;
    isSending = true;
    try {
      await matrixViewModel.sendImage(roomId);
    } catch (e) {
      console.error('[MatrixDetail][sendMedia] Failed to send media:', e);
    } finally {
      isSending = false;
      await tick();
      messageInputRef?.focus();
    }
  }

  $: formattedRoomName = item.title || 'Matrix Room';
</script>

<div class="matrix-detail-panel {className}">
  <RoomHeader title={formattedRoomName} messageCount={$messages.length} roomId={item.id} />

  <!-- Messages Container -->
  <div class="messages-container" bind:this={messagesContainer}>
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
          <div
            class="rounded-full bg-gray-200 px-4 py-2 text-sm text-gray-600 dark:bg-gray-700 dark:text-gray-400"
          >
            Beginning of conversation
          </div>
        </div>
      </div>
    {/if}

    <!-- Messages -->
    {#each $messages as message, index (message.id)}
      {@const isFirstInGroup = index === 0 || $messages[index - 1].sender !== message.sender}
      {@const isLastInGroup =
        index === $messages.length - 1 || $messages[index + 1].sender !== message.sender}
      {@const nextIsUnread = index < $messages.length - 1 && $messages[index + 1].timestamp > minOtherReadTs}
      <MessageItem
        {message}
        {isFirstInGroup}
        {isLastInGroup}
        {mediaVersion}
        {minOtherReadTs}
        {nextIsUnread}
        on:openImage={openLightbox}
      />
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

  <MessageInput
    bind:this={messageInputRef}
    {isSending}
    on:send={(e) => sendMessage(e.detail)}
    on:sendMedia={() => sendMedia()}
  />

  {#if lightboxUrl}
    <div class="lightbox" on:click={closeLightbox}>
      <div class="lightbox-content" on:click|stopPropagation>
        <img src={lightboxUrl} alt={lightboxDesc} />
      </div>
      <button class="lightbox-close" aria-label="Close" on:click={closeLightbox}>×</button>
    </div>
  {/if}
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
    0% {
      transform: rotate(0deg);
    }
    100% {
      transform: rotate(360deg);
    }
  }
  /* Sticky wrapper: sticks the button to the bottom edge of the scroll area */
  .jump-to-bottom-wrap {
    position: sticky;
    bottom: 0; /* stick to bottom of the messages container */
    display: flex;
    justify-content: flex-end;
    pointer-events: none; /* let clicks pass through except on the button */
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
    box-shadow: 0 8px 20px rgba(0, 0, 0, 0.25);
    cursor: pointer;
    opacity: 0.95;
    transition:
      transform 120ms ease,
      opacity 120ms ease;
  }

  .jump-to-bottom:hover {
    transform: translateY(-1px);
    opacity: 1;
  }
  .jump-to-bottom:active {
    transform: translateY(0);
  }

  .jump-to-bottom .icon {
    width: 20px;
    height: 20px;
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
    background: rgba(255, 255, 255, 0.2);
    color: #fff;
    backdrop-filter: saturate(180%) blur(6px);
  }

  /* Lightbox styles */
  .lightbox {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.85);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1000;
  }
  .lightbox-content {
    max-width: 95vw;
    max-height: 95vh;
  }
  .lightbox-content img {
    max-width: 95vw;
    max-height: 95vh;
    object-fit: contain;
    border-radius: 6px;
    box-shadow: 0 10px 30px rgba(0,0,0,0.5);
  }
  .lightbox-close {
    position: fixed;
    top: 12px;
    right: 14px;
    width: 36px;
    height: 36px;
    border-radius: 9999px;
    border: none;
    background: rgba(255,255,255,0.15);
    color: #fff;
    font-size: 24px;
    line-height: 1;
    cursor: pointer;
  }
</style>
