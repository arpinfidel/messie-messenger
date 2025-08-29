<!-- GenericTimelineItem.svelte -->
<script lang="ts">
  import type { TimelineItem } from '@/models/shared/TimelineItem';
  import { createEventDispatcher } from 'svelte';

  export let item: TimelineItem;

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
    }
  };

  $: config = typeConfig[item.type] || typeConfig.default;
  $: formattedDate = new Date(item.timestamp).toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  });
</script>

<div
  class="timeline-item group relative overflow-hidden rounded-xl border border-gray-200 bg-white/80 backdrop-blur-sm transition-all duration-300 hover:scale-[1.02] hover:shadow-lg hover:shadow-gray-200/50 dark:border-gray-700 dark:bg-gray-800/80 dark:hover:shadow-gray-900/25"
  on:click={() => selectItem(item)}
  on:keydown={(e) => e.key === 'Enter' && selectItem(item)}
  role="button"
  tabindex="0"
>
  <!-- Subtle gradient overlay -->
  <div class="absolute inset-0 bg-gradient-to-br from-white/50 to-transparent opacity-0 transition-opacity duration-300 group-hover:opacity-100 dark:from-white/5"></div>
  
  <!-- Content container -->
  <div class="relative z-10 p-5">
    <!-- Header with icon and timestamp -->
    <div class="mb-3 flex items-start justify-between">
      <div class="flex items-center space-x-3">
        <!-- Type icon with gradient background -->
        <div class={`flex h-10 w-10 items-center justify-center rounded-full bg-gradient-to-br ${config.gradient} text-white shadow-sm`}>
          <span class="text-lg">{config.icon}</span>
        </div>
        
        <!-- Title -->
        <h3 class="max-w-[200px] truncate text-lg font-semibold text-gray-900 transition-colors group-hover:text-gray-700 dark:text-gray-100 dark:group-hover:text-gray-200">
          {item.title}
        </h3>
      </div>
      
      <!-- Timestamp -->
      <time class="flex-shrink-0 text-sm font-medium text-gray-500 dark:text-gray-400">
        {formattedDate}
      </time>
    </div>
    
    <!-- Description -->
    <p class="mb-4 line-clamp-2 text-gray-600 transition-colors group-hover:text-gray-700 dark:text-gray-300 dark:group-hover:text-gray-200">
      {item.description || 'No description available'}
    </p>
    
    <!-- Footer with type badge and interaction hint -->
    <div class="flex items-center justify-between">
      <!-- Type badge -->
      <span class={`inline-flex items-center rounded-full px-3 py-1.5 text-xs font-semibold uppercase tracking-wide text-white ring-2 ring-offset-2 ring-offset-white transition-all bg-gradient-to-r ${config.gradient} ${config.ringColor} dark:ring-offset-gray-800`}>
        {item.type}
      </span>
      
      <!-- Interaction hint -->
      <div class="flex items-center text-xs text-gray-400 opacity-0 transition-all duration-300 group-hover:opacity-100 dark:text-gray-500">
        <span>Click to view</span>
        <svg class="ml-1 h-3 w-3 transition-transform duration-300 group-hover:translate-x-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
        </svg>
      </div>
    </div>
  </div>
  
  <!-- Subtle border highlight on hover -->
  <div class="absolute inset-0 rounded-xl opacity-0 transition-opacity duration-300 group-hover:opacity-100" style="box-shadow: inset 0 0 0 1px rgba(59, 130, 246, 0.15);"></div>
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
