<!-- GenericTimelineItem.svelte -->
<script lang="ts">
  import type { TimelineItem } from '@/models/shared/TimelineItem';
  import { createEventDispatcher } from 'svelte';
  import { format, isSameDay, isSameYear } from 'date-fns';

  export let item: TimelineItem;

  const now = new Date();

  function formatTimelineDate(timestamp: number): string {
    // Blank out missing/zero timestamps
    if (!timestamp || !Number.isFinite(timestamp) || timestamp <= 0) return '';
    const date = new Date(timestamp);

    if (isSameDay(date, now)) {
      return format(date, 'HH:mm'); // hh:mm (24h) if within same day
    } else if (isSameYear(date, now)) {
      return format(date, 'dd/MM'); // dd/mm if same year
    } else {
      return format(date, 'MM/yyyy'); // mm/yyyy if not same year
    }
  }

  const dispatch = createEventDispatcher();

  function selectItem(selectedItem: TimelineItem) {
    dispatch('itemSelected', selectedItem);
  }

  // Type-based styling configuration
  const typeConfig = {
    matrix: {
      icon: '💬',
      gradient: 'from-emerald-500 to-teal-600',
      ringColor: 'ring-emerald-200 dark:ring-emerald-800',
    },
    email: {
      icon: '📧',
      gradient: 'from-blue-500 to-indigo-600',
      ringColor: 'ring-blue-200 dark:ring-blue-800',
    },
    todo: {
      icon: '✅',
      gradient: 'from-purple-500 to-violet-600',
      ringColor: 'ring-purple-200 dark:ring-purple-800',
    },
    calendar: {
      icon: '📅',
      gradient: 'from-red-500 to-pink-600',
      ringColor: 'ring-red-200 dark:ring-red-800',
    },
    Message: {
      icon: '💬',
      gradient: 'from-sky-500 to-cyan-600',
      ringColor: 'ring-sky-200 dark:ring-sky-800',
    },
    Call: {
      icon: '📞',
      gradient: 'from-green-500 to-lime-600',
      ringColor: 'ring-green-200 dark:ring-green-800',
    },
    chat: {
      icon: '🗣️',
      gradient: 'from-orange-500 to-amber-600',
      ringColor: 'ring-orange-200 dark:ring-orange-800',
    },
    default: {
      icon: '📄',
      gradient: 'from-gray-500 to-slate-600',
      ringColor: 'ring-gray-200 dark:ring-gray-800',
    },
  };

  $: config = typeConfig[item.type] || typeConfig.default;
  $: formattedDate = formatTimelineDate(item.timestamp);
</script>

<div
  class="timeline-item group relative overflow-hidden rounded-xl border border-gray-200 bg-white/80 backdrop-blur-sm transition-all duration-300 hover:scale-[1.02] hover:shadow-lg hover:shadow-gray-200/50 dark:border-gray-700 dark:bg-gray-800/80 dark:hover:shadow-gray-900/25"
  on:click={() => selectItem(item)}
  on:keydown={(e) => e.key === 'Enter' && selectItem(item)}
  role="button"
  tabindex="0"
>
  <!-- Subtle gradient overlay -->
  <div
    class="absolute inset-0 bg-gradient-to-br from-white/50 to-transparent opacity-0 transition-opacity duration-300 group-hover:opacity-100 dark:from-white/5"
  ></div>

  <!-- Content container -->
  <div class="relative z-10 flex h-full p-3">
    <!-- Avatar column -->
    <div class="mr-3 flex w-12 flex-shrink-0 items-start justify-center">
      {#if item.avatarUrl}
        <img src={item.avatarUrl} alt="avatar" class="h-10 w-10 rounded-full object-cover shadow-sm" />
      {:else}
        <!-- Round fallback avatar with emoji -->
        <div
          class={`relative flex h-10 w-10 items-center justify-center rounded-full bg-gradient-to-br ${config.gradient} text-white shadow-sm`}
        >
          <span class="text-lg">{config.icon}</span>
        </div>
      {/if}
    </div>
    <div class="flex-grow min-w-0">
      <!-- First row: room name, then date and item type capsule stacked vertically -->
      <div class="mb-1 flex items-start justify-between">
        <div class="flex max-w-[calc(100%-100px)] min-w-0 items-center">
          <h3
            class="truncate text-base font-semibold text-gray-900 transition-colors group-hover:text-gray-700 dark:text-gray-100 dark:group-hover:text-gray-200"
          >
            {item.title}
          </h3>
          {#if item.unreadCount && item.unreadCount > 0}
            <span
              class="ml-2 rounded-full bg-blue-600 px-2 text-xs text-white"
              >{item.unreadCount > 99 ? '99+' : item.unreadCount}</span
            >
          {/if}
        </div>

        <!-- Date and Item Type Capsule -->
        <div class="flex-shrink-0 text-right">
          <time class="block text-xs font-medium text-gray-500 dark:text-gray-400">
            {formattedDate}
          </time>
        </div>
      </div>

      <!-- Second row: Description (Preview) -->
      <p
        class="line-clamp-2 h-10 min-w-0 break-words text-sm leading-5 text-gray-600 transition-colors group-hover:text-gray-700 dark:text-gray-300 dark:group-hover:text-gray-200"
      >
        {item.description || 'No description available'}
      </p>
    </div>
  </div>

  <!-- Interaction hint (moved to be part of the main content for compactness, or removed if not needed) -->
  <!-- For now, let's keep it simple and remove the interaction hint to make it more compact -->
  <!-- Subtle border highlight on hover -->
  <div
    class="absolute inset-0 rounded-xl opacity-0 transition-opacity duration-300 group-hover:opacity-100"
    style="box-shadow: inset 0 0 0 1px rgba(59, 130, 246, 0.15);"
  ></div>
</div>

<style>
  .timeline-item {
    cursor: pointer;
  }

  .timeline-item:focus {
    outline: none;
    @apply ring-2 ring-blue-500 ring-offset-2 ring-offset-gray-900;
  }

  /* Line clamp utility for description */
  .line-clamp-2 {
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
    /* Standard property for compatibility */
    line-clamp: 2;
  }
</style>
