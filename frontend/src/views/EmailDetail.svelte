<script lang="ts">
  import type { TimelineItem } from '../models/shared/TimelineItem';
  import { EmailViewModel } from '@/viewmodels/email/EmailViewModel';
  import type { EmailMessageHeader } from '@/api/generated/models/EmailMessageHeader';
  import { onMount } from 'svelte';

  export let item: TimelineItem;
  const emailVM = EmailViewModel.getInstance();
  let messages: EmailMessageHeader[] = [];

  const unsub = emailVM.getSelectedMessages().subscribe((v) => (messages = v));
  onMount(() => {
    return () => {
      unsub();
    };
  });
</script>

<div class="flex h-full flex-col">
  <div class="border-b border-gray-800 p-4">
    <div class="text-sm text-gray-400">
      {item.id === 'email-inbox' ? 'All Mail' : item.id === 'email-important' ? 'Important' : 'Email Thread'}
    </div>
    <h2 class="truncate text-xl font-semibold text-gray-100">{item.title}</h2>
    {#if item.description}
      <div class="truncate text-sm text-gray-400">{item.description}</div>
    {/if}
  </div>

  <div class="flex-1 overflow-y-auto p-4 space-y-3">
    {#if messages.length === 0}
      <div class="text-gray-400">No messages loaded yet.</div>
    {:else}
      {#each messages as m, i}
        <div class="rounded-lg border border-gray-800 bg-gray-850 p-3">
          <div class="mb-1 text-xs text-gray-400">
            <span class="font-medium text-gray-300">{m.from || 'Unknown sender'}</span>
            <span class="mx-2">•</span>
            <span>{m.date ? new Date(m.date).toLocaleString() : ''}</span>
          </div>
          <div class="text-gray-100">{m.subject || '(no subject)'}</div>
        </div>
      {/each}
    {/if}
  </div>
</div>

<style>
  /* Slightly darker gray for message cards */
  .bg-gray-850 { background-color: #1f2937; }
  .truncate { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .space-y-3 > :not([hidden]) ~ :not([hidden]) { --tw-space-y-reverse: 0; margin-top: calc(0.75rem * calc(1 - var(--tw-space-y-reverse))); margin-bottom: calc(0.75rem * var(--tw-space-y-reverse)); }
</style>
