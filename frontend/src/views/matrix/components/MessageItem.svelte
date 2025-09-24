<script lang="ts">
  import type { MatrixMessage, MatrixMessageVersion } from '@/viewmodels/matrix/MatrixTimelineService';
  import { createEventDispatcher, onMount, afterUpdate, tick } from 'svelte';
  import PopupMenu from '@/views/shared/PopupMenu.svelte';
  import { Check, CheckCheck } from 'lucide-svelte';

  export let message: MatrixMessage;
  export let isFirstInGroup: boolean;
  export let isLastInGroup: boolean;
  export let mediaVersion: number = 0;
  // Max read timestamp by other members (passed from parent)
  export let minOtherReadTs: number = 0;
  export let nextIsUnread: boolean = false;

  const dispatch = createEventDispatcher<{ openImage: { url: string; description?: string } }>();

  let container: HTMLDivElement | undefined;
  let showMenu = false;
  let showHistory = false;
  let previousVersions: MatrixMessageVersion[] = [];
  let hasEditHistory = false;
  let editedTooltip = '';
  let formattedTimestamp = '';
  let showTimestampMeta = false;
  let timestampEl: HTMLDivElement | null = null;
  let timestampSpacer: string | null = null;
  let menuButton: HTMLButtonElement | null = null;

  function onImageClick() {
    if (message.imageUrl) {
      dispatch('openImage', { url: message.imageUrl, description: message.body });
    }
  }

  function toggleMenu(event: MouseEvent) {
    event.stopPropagation();
    showMenu = !showMenu;
    if (!showMenu) {
      showHistory = false;
    }
  }

  function toggleHistory(event: MouseEvent) {
    event.stopPropagation();
    if (!hasEditHistory) return;
    showHistory = !showHistory;
    if (showHistory) {
      showMenu = false;
    }
  }

  function closeHistory() {
    showHistory = false;
  }

  function closeOverlays() {
    showMenu = false;
    showHistory = false;
  }

  async function updateTimestampSpacer() {
    if (!showTimestampMeta) {
      if (timestampSpacer !== null) {
        timestampSpacer = null;
      }
      return;
    }

    await tick();

    if (!timestampEl) {
      return;
    }

    const measuredWidth = timestampEl.offsetWidth;
    if (measuredWidth <= 0) {
      return;
    }

    const nextValue = `${Math.ceil(measuredWidth + 4)}px`;
    if (timestampSpacer !== nextValue) {
      timestampSpacer = nextValue;
    }
  }

  $: hasEditHistory = Array.isArray(message.editHistory) && message.editHistory.length > 0;
  $: previousVersions = hasEditHistory ? [...(message.editHistory ?? [])].reverse() : [];
  $: if (!hasEditHistory) {
    showHistory = false;
  }

  $:
    editedTooltip =
      message.lastEditedTimestamp != null
        ? new Date(message.lastEditedTimestamp).toLocaleString('en-US', {
            month: 'short',
            day: 'numeric',
            hour: '2-digit',
            minute: '2-digit',
            hour12: false,
          })
        : '';

  $:
    formattedTimestamp = new Date(message.timestamp).toLocaleTimeString('en-US', {
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    });

  $: showTimestampMeta = isLastInGroup || (nextIsUnread && message.isSelf);

  onMount(() => {
    const handleClick = (event: MouseEvent) => {
      if (!container?.contains(event.target as Node)) {
        closeOverlays();
      }
    };
    const handleKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        closeOverlays();
      }
    };
    document.addEventListener('click', handleClick);
    document.addEventListener('keydown', handleKey);
    void updateTimestampSpacer();
    return () => {
      document.removeEventListener('click', handleClick);
      document.removeEventListener('keydown', handleKey);
    };
  });

  afterUpdate(() => {
    void updateTimestampSpacer();
  });
</script>

<div class="message-wrapper {message.isSelf ? 'self' : 'other'}" bind:this={container}>
  {#if !message.isSelf}
    <div class="avatar-slot other">
      {#if isFirstInGroup && message.senderAvatarUrl}
        {#key mediaVersion}
          <img src={message.senderAvatarUrl} alt={message.senderDisplayName} class="avatar-small" />
        {/key}
      {:else}
        <div class="avatar-spacer"></div>
      {/if}
    </div>
  {/if}

  <div
    class="message-bubble {message.isSelf ? 'self' : 'other'} {isFirstInGroup ? 'first-in-group' : ''} {isLastInGroup ? 'last-in-group' : ''} {showTimestampMeta ? 'has-timestamp' : ''}"
    style:--timestamp-spacer={timestampSpacer ?? undefined}
  >
    {#if !message.isSelf && isFirstInGroup}
      <div class="sender-name">{message.senderDisplayName}</div>
    {/if}

    {#if message.msgtype === 'm.image'}
      <div class="image-wrapper">
        {#key mediaVersion}
          {#if message.imageUrl}
            <img
              src={message.imageUrl}
              alt={message.body}
              class="message-image clickable"
              referrerpolicy="no-referrer"
              loading="lazy"
              on:click|stopPropagation={onImageClick}
            />
          {:else}
            <div class="image-placeholder">
              <div class="loading-spinner small"></div>
              <span>Decrypting image…</span>
            </div>
          {/if}
        {/key}
      </div>
    {:else if message.msgtype === 'm.file'}
      <div class="file-wrapper">
        {#key mediaVersion}
          {#if message.fileUrl}
            <a
              href={message.fileUrl}
              download={message.fileName}
              class="file-link"
            >
              📎 Download {message.fileName}
            </a>
          {:else}
            <span class="file-link">📎 {message.fileName}</span>
          {/if}
        {/key}
      </div>
    {/if}
    <div class="message-content">{message.body}</div>

    {#if message.isEdited && !showTimestampMeta}
      <div class="message-inline-meta">
        <span class="edited-indicator" title={editedTooltip}>Edited</span>
      </div>
    {/if}

    {#if showTimestampMeta}
      <div class="message-timestamp" bind:this={timestampEl}>
        {#if message.isEdited}
          <span class="edited-indicator" title={editedTooltip}>Edited</span>
        {/if}
        <span>{formattedTimestamp}</span>
        {#if message.isSelf}
          <!-- <br>{minOtherReadTs}<br>{message.timestamp} -->
          {#if minOtherReadTs > 0 && message.timestamp <= minOtherReadTs}
          <!-- Considered read: render double colored -->
          <span class="tick-icon double colored" aria-label="Read by others">
            <CheckCheck size={18} aria-hidden="true" />
          </span>
          {:else}
            <!-- Sent: single check -->
            <span class="tick-icon single" aria-label="Sent">
              <Check size={18} aria-hidden="true" />
            </span>
          {/if}
        {/if}
      </div>
    {/if}
  </div>

  <div
    class="context-menu-slot {message.isSelf ? 'self' : 'other'}"
    class:open={showMenu || showHistory}
  >
    <button
      bind:this={menuButton}
      class="context-menu-button"
      type="button"
      aria-haspopup="true"
      aria-expanded={showMenu}
      aria-label="Message actions"
      on:click|stopPropagation={toggleMenu}
    >
      ⋯
    </button>
    <PopupMenu
      anchor={menuButton}
      show={showMenu}
      placement={message.isSelf ? 'left' : 'right'}
      align="start"
      offset={8}
      menuClass={`message-actions-menu ${message.isSelf ? 'self' : 'other'}`}
      on:close={() => (showMenu = false)}
    >
      <button class="message-actions-item" type="button" disabled>
        ✏️ Edit (coming soon)
      </button>
      {#if hasEditHistory}
        <button class="message-actions-item" type="button" on:click|stopPropagation={toggleHistory}>
          🕓 {showHistory ? 'Hide edit history' : 'View edit history'}
        </button>
      {/if}
    </PopupMenu>
  </div>

  {#if showHistory && hasEditHistory}
    <div
      class="edit-history-popover {message.isSelf ? 'self' : 'other'}"
      role="dialog"
      aria-label="Message edit history"
      tabindex="-1"
    >
      <div class="history-header">
        <span>Previous versions</span>
        <button
          class="close-history"
          type="button"
          aria-label="Close edit history"
          on:click={closeHistory}
        >
          ×
        </button>
      </div>
      <ul>
        {#each previousVersions as version, idx}
          {@const isOriginal = idx === previousVersions.length - 1}
          <li>
            <div class="history-body">{version.body}</div>
            <div class="history-meta">
              {new Date(version.timestamp).toLocaleString('en-US', {
                month: 'short',
                day: 'numeric',
                hour: '2-digit',
                minute: '2-digit',
                hour12: false,
              })}
              · {version.senderDisplayName}
              {#if isOriginal}
                · Original message
              {:else}
                · Previous edit
              {/if}
            </div>
          </li>
        {/each}
      </ul>
    </div>
  {/if}
</div>

<style>
  .message-wrapper {
    display: flex;
    margin-bottom: 2px;
    position: relative;
    align-items: flex-start;
  }
  .message-wrapper.self { justify-content: flex-end; }
  .message-wrapper.other { justify-content: flex-start; }

  .avatar-slot { width: 28px; display: flex; align-items: flex-start; flex-shrink: 0; }
  .avatar-slot.other { margin-right: 8px; }
  .avatar-small { width: 24px; height: 24px; border-radius: 9999px; object-fit: cover; }
  .avatar-spacer { width: 24px; height: 24px; }

  .message-bubble {
    max-width: 75%;
    padding: 0.5rem 0.625rem;
    border-radius: 1rem;
    background: var(--color-input-bg);
    color: var(--color-text);
    position: relative;
    word-break: break-word;
    transition: all 0.2s ease;
    line-height: 1.3;
  }
  .message-bubble:hover { background: var(--color-bubble-other-hover); }
  .message-bubble.self { background: var(--color-bubble-self); color: white; }
  .message-bubble.self:hover { background: var(--color-bubble-self-hover); }
  .message-bubble.other { background: var(--color-bubble-other); color: var(--color-text); }
  .message-bubble.other:hover { background: var(--color-bubble-other-hover); }

  
  /* .message-bubble.first-in-group.other { border-top-left-radius: 1rem; margin-top: 6px; }
  .message-bubble.first-in-group.self { border-top-right-radius: 1rem; margin-top: 6px; }
  .message-bubble.last-in-group.other { border-bottom-left-radius: 1rem; margin-bottom: 0.75rem; }
  .message-bubble.last-in-group.self { border-bottom-right-radius: 1rem; margin-bottom: 0.75rem; } */
  
  .message-bubble.first-in-group.other { border-top-left-radius: 1rem; border-bottom-left-radius: 0.25rem; }
  .message-bubble.first-in-group.self { border-top-right-radius: 1rem; border-bottom-right-radius: 0.25rem; }
  .message-bubble.last-in-group.other { border-bottom-left-radius: 1rem; border-top-left-radius: 0.25rem; margin-bottom: 0.75rem; }
  .message-bubble.last-in-group.self { border-bottom-right-radius: 1rem; border-top-right-radius: 0.25rem; margin-bottom: 0.75rem; }
  .message-bubble.first-in-group.last-in-group.other { border-radius: 1rem; margin-bottom: 0.5rem; }
  .message-bubble.first-in-group.last-in-group.self { border-radius: 1rem; margin-bottom: 0.5rem; }
  .message-bubble:not(.first-in-group):not(.last-in-group).other { border-top-left-radius: 0.25rem; border-bottom-left-radius: 0.25rem; }
  .message-bubble:not(.first-in-group):not(.last-in-group).self { border-top-right-radius: 0.25rem; border-bottom-right-radius: 0.25rem; }

  .sender-name { font-size: 0.75rem; font-weight: 600; color: #60a5fa; margin-bottom: 0.25rem; }
  .message-content { white-space: pre-wrap; line-height: 1.4; display: block; }

  .message-image { max-width: 100%; max-height: 100%; object-fit: contain; display: block; border-radius: 0.5rem; }
  .message-image.clickable { cursor: zoom-in; }
  .image-wrapper { max-width: 360px; max-height: 360px; width: 100%; display: inline-flex; align-items: center; justify-content: center; overflow: hidden; border-radius: 0.5rem; background: var(--color-input-bg); margin-bottom: 1rem; }
  .image-placeholder { min-width: 180px; min-height: 140px; display: inline-flex; align-items: center; justify-content: center; gap: 0.5rem; color: var(--color-text-muted); }
  .file-wrapper { max-width: 360px; width: 100%; display: inline-flex; align-items: center; justify-content: center; background: var(--color-input-bg); border-radius: 0.5rem; padding: 0.75rem; margin-bottom: 0.5rem; }
  .file-link { text-decoration: none; color: inherit; }
  .file-link:hover { text-decoration: underline; }

  .message-timestamp {
    font-size: 0.65rem;
    line-height: 1;
    opacity: 0.7;
    position: absolute;
    right: 0.5rem;
    bottom: 0.35rem;
    margin: 0;
    text-align: right;
    pointer-events: none;
    display: flex;
    gap: 0.35rem;
    align-items: center;
    justify-content: flex-end;
  }
  .message-timestamp span { display: inline-flex; }
  .message-bubble.has-timestamp .message-content::after {
    content: '';
    display: inline-block;
    width: var(--timestamp-spacer, 4ch);
  }
  .message-bubble.has-timestamp.self .message-content::after {
    width: var(--timestamp-spacer, 6.5ch);
  }

  .message-inline-meta {
    margin-top: 0.25rem;
    font-size: 0.65rem;
    opacity: 0.7;
    display: flex;
    justify-content: flex-end;
  }

  .edited-indicator { font-size: 0.65rem; opacity: 0.75; }
  .message-bubble.self .edited-indicator { color: rgba(255,255,255,0.85); }
  .message-bubble.other .edited-indicator { color: var(--color-text-muted); }

  /* Ticks: overlapping SVG checks with subtle shadow for contrast */
  .tick-icon { margin-left: 0.35rem; display: inline-flex; align-items: center; justify-content: center; vertical-align: middle; filter: drop-shadow(0 0 1px rgba(0,0,0,0.6)); }
  /* Default ticks inherit bubble text color; make them slightly brighter for legibility */
  .message-bubble.self .tick-icon { color: rgba(255,255,255,0.95); }
  /* Ensure colored state overrides the self-bubble default */
  .message-bubble.self .tick-icon.colored { color: var(--wa-tick-blue, #34b7f1); }
  /* WhatsApp-like blue for full-read state, tuned for higher contrast */
  .tick-icon.colored { color: var(--wa-tick-blue, #34b7f1); }

  .context-menu-slot {
    display: flex;
    align-items: center;
    position: relative;
    width: 28px;
    flex-shrink: 0;
    opacity: 0;
    pointer-events: none;
    transition: opacity 0.15s ease;
  }
  .context-menu-slot.open,
  .message-wrapper:hover .context-menu-slot,
  .context-menu-slot:focus-within {
    opacity: 1;
    pointer-events: auto;
  }
  .message-wrapper.self .context-menu-slot { order: 0; margin-right: 6px; }
  .message-wrapper.self .message-bubble { order: 1; }
  .message-wrapper.other .context-menu-slot { order: 2; margin-left: 6px; }
  .message-wrapper.other .message-bubble { order: 1; }
  .message-wrapper.other .avatar-slot { order: 0; }

  .context-menu-button {
    width: 24px;
    height: 24px;
    border-radius: 9999px;
    border: none;
    background: transparent;
    color: var(--color-text-muted);
    cursor: pointer;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    font-size: 1.1rem;
    transition: background 0.15s ease, color 0.15s ease;
  }
  .context-menu-button:hover,
  .context-menu-button:focus-visible {
    background: rgba(255,255,255,0.1);
    color: var(--color-text);
    outline: none;
  }

  :global(.message-actions-menu) {
    background: var(--color-panel);
    border: 1px solid var(--color-panel-border, rgba(255,255,255,0.08));
    box-shadow: 0 10px 30px rgba(0,0,0,0.35);
    min-width: 180px;
    padding: 0.35rem 0;
    color: inherit;
  }
  :global(.message-actions-menu.self) {
    transform-origin: top right;
  }
  :global(.message-actions-menu.other) {
    transform-origin: top left;
  }

  :global(.message-actions-item) {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    width: 100%;
    padding: 0.45rem 0.75rem;
    background: none;
    border: none;
    color: inherit;
    font-size: 0.85rem;
    cursor: pointer;
    text-align: left;
  }
  :global(.message-actions-item:hover:not(:disabled)),
  :global(.message-actions-item:focus-visible:not(:disabled)) {
    background: rgba(255,255,255,0.08);
    outline: none;
  }
  :global(.message-actions-item:disabled) {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .edit-history-popover {
    position: absolute;
    top: calc(100% + 0.5rem);
    background: var(--color-panel);
    border-radius: 0.75rem;
    box-shadow: 0 12px 32px rgba(0,0,0,0.35);
    padding: 0.75rem;
    max-width: min(320px, 80vw);
    z-index: 25;
    border: 1px solid var(--color-panel-border, rgba(255,255,255,0.08));
  }
  .edit-history-popover.self { right: 0; }
  .edit-history-popover.other { left: 0; }

  .history-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    font-size: 0.8rem;
    font-weight: 600;
    margin-bottom: 0.5rem;
  }

  .close-history {
    width: 1.5rem;
    height: 1.5rem;
    border-radius: 9999px;
    border: none;
    background: transparent;
    color: inherit;
    cursor: pointer;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    font-size: 1rem;
    transition: background 0.15s ease;
  }
  .close-history:hover,
  .close-history:focus-visible {
    background: rgba(255,255,255,0.08);
    outline: none;
  }

  .edit-history-popover ul {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    max-height: 220px;
    overflow-y: auto;
  }

  .edit-history-popover li {
    font-size: 0.8rem;
    color: var(--color-text);
  }

  .history-body { white-space: pre-wrap; line-height: 1.3; }
  .history-meta { margin-top: 0.25rem; font-size: 0.7rem; color: var(--color-text-muted); }
</style>
