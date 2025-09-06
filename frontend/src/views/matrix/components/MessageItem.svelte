<script lang="ts">
  import type { MatrixMessage } from '@/viewmodels/matrix/MatrixTimelineService';
  import { createEventDispatcher } from 'svelte';

  export let message: MatrixMessage;
  export let isFirstInGroup: boolean;
  export let isLastInGroup: boolean;
  export let mediaVersion: number = 0;

  const dispatch = createEventDispatcher<{ openImage: { url: string; description?: string } }>();

  function onImageClick() {
    if (message.imageUrl) {
      dispatch('openImage', { url: message.imageUrl, description: message.description });
    }
  }
</script>

<div class="message-wrapper {message.isSelf ? 'self' : 'other'}">
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

  <div class="message-bubble {message.isSelf ? 'self' : 'other'} {isFirstInGroup ? 'first-in-group' : ''} {isLastInGroup ? 'last-in-group' : ''}">
    {#if !message.isSelf && isFirstInGroup}
      <div class="sender-name">{message.senderDisplayName}</div>
    {/if}

    {#if message.msgtype === 'm.image'}
      <div class="image-wrapper">
        {#key mediaVersion}
          {#if message.imageUrl}
            <img
              src={message.imageUrl}
              alt={message.description}
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
    {:else}
      <div class="message-content">{message.description}</div>
    {/if}

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

<style>
  .message-wrapper {
    display: flex;
    margin-bottom: 2px;
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
  .message-bubble.self { background: var(--color-bubble-self); color: white; margin-left: auto; }
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
  .message-content { white-space: pre-wrap; display: inline; line-height: 1.4; }

  .message-image { max-width: 100%; max-height: 100%; object-fit: contain; display: block; border-radius: 0.5rem; }
  .message-image.clickable { cursor: zoom-in; }
  .image-wrapper { max-width: 360px; max-height: 360px; width: 100%; display: inline-flex; align-items: center; justify-content: center; overflow: hidden; border-radius: 0.5rem; background: var(--color-input-bg); }
  .image-placeholder { min-width: 180px; min-height: 140px; display: inline-flex; align-items: center; justify-content: center; gap: 0.5rem; color: var(--color-text-muted); }

  .message-timestamp { font-size: 0.65rem; line-height: 1; opacity: 0.7; position: absolute; right: 0.5rem; bottom: 0.35rem; margin: 0; text-align: right; pointer-events: none; }
  .message-bubble.last-in-group .message-content::after { content: ''; display: inline-block; width: 3ch; }
</style>
