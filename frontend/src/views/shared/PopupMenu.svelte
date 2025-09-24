<script lang="ts">
  import { createEventDispatcher, onMount, onDestroy, afterUpdate } from 'svelte';
  export let show: boolean = false;
  export let anchor: HTMLElement | null = null;
  export let placement: 'auto' | 'top' | 'bottom' | 'left' | 'right' = 'auto';
  export let align: 'start' | 'center' | 'end' = 'start';
  export let offset: number = 4;
  export let collisionPadding: number = 8;
  export let menuClass: string = '';
  const dispatch = createEventDispatcher<{ close: void }>();
  let menuEl: HTMLDivElement | null = null;
  let positionListenersAttached = false;

  function updatePosition() {
    if (!anchor || !menuEl) return;
    const rect = anchor.getBoundingClientRect();
    const menuRect = menuEl.getBoundingClientRect();
    const viewportWidth = document.documentElement.clientWidth;
    const viewportHeight = document.documentElement.clientHeight;

    const scrollX = window.scrollX;
    const scrollY = window.scrollY;
    const minLeft = scrollX + collisionPadding;
    const maxLeft = scrollX + viewportWidth - collisionPadding - menuRect.width;
    const minTop = scrollY + collisionPadding;
    const maxTop = scrollY + viewportHeight - collisionPadding - menuRect.height;

    const clamp = (value: number, min: number, max: number) => {
      if (max < min) {
        return min;
      }
      return Math.min(Math.max(value, min), max);
    };

    const alignHorizontal = () => {
      if (align === 'end') {
        return rect.right + scrollX - menuRect.width;
      }
      if (align === 'center') {
        return rect.left + scrollX + rect.width / 2 - menuRect.width / 2;
      }
      return rect.left + scrollX;
    };

    const alignVertical = () => {
      if (align === 'end') {
        return rect.bottom + scrollY - menuRect.height;
      }
      if (align === 'center') {
        return rect.top + scrollY + rect.height / 2 - menuRect.height / 2;
      }
      return rect.top + scrollY;
    };

    let left = alignHorizontal();
    let top = alignVertical();

    const placeBottom = () => rect.bottom + scrollY + offset;
    const placeTop = () => rect.top + scrollY - menuRect.height - offset;
    const placeRight = () => rect.right + scrollX + offset;
    const placeLeft = () => rect.left + scrollX - menuRect.width - offset;

    switch (placement) {
      case 'top': {
        top = placeTop();
        left = alignHorizontal();
        top = clamp(top, minTop, maxTop);
        break;
      }
      case 'bottom': {
        top = placeBottom();
        if (top > maxTop) {
          top = clamp(top, minTop, maxTop);
        }
        break;
      }
      case 'left': {
        top = alignVertical();
        left = placeLeft();
        left = clamp(left, minLeft, maxLeft);
        break;
      }
      case 'right': {
        top = alignVertical();
        left = placeRight();
        left = clamp(left, minLeft, maxLeft);
        break;
      }
      case 'auto':
      default: {
        top = placeBottom();

        const bottomOverflow = top + menuRect.height - (scrollY + viewportHeight - collisionPadding);
        if (bottomOverflow > 0) {
          const abovePosition = placeTop();
          if (abovePosition >= minTop) {
            top = abovePosition;
          } else {
            top = clamp(top - bottomOverflow, minTop, maxTop);
          }
        }
        break;
      }
    }

    left = clamp(left, minLeft, maxLeft);
    top = clamp(top, minTop, maxTop);

    menuEl.style.top = `${top}px`;
    menuEl.style.left = `${left}px`;
  }

  function attachPositionListeners() {
    if (positionListenersAttached) return;
    window.addEventListener('resize', updatePosition);
    window.addEventListener('scroll', updatePosition, true);
    positionListenersAttached = true;
  }

  function detachPositionListeners() {
    if (!positionListenersAttached) return;
    window.removeEventListener('resize', updatePosition);
    window.removeEventListener('scroll', updatePosition, true);
    positionListenersAttached = false;
  }

  function handleClickOutside(event: MouseEvent) {
    if (
      show &&
      menuEl &&
      !menuEl.contains(event.target as Node) &&
      anchor &&
      !anchor.contains(event.target as Node)
    ) {
      dispatch('close');
    }
  }

  onMount(() => {
    document.addEventListener('click', handleClickOutside, true);
  });

  onDestroy(() => {
    document.removeEventListener('click', handleClickOutside, true);
    detachPositionListeners();
  });

  afterUpdate(() => {
    if (show && anchor) {
      updatePosition();
      attachPositionListeners();
    } else {
      detachPositionListeners();
    }
  });
</script>

{#if show}
  <div
    bind:this={menuEl}
    class="fixed z-50 rounded-lg border border-gray-200 bg-white p-2 shadow-lg dark:border-gray-700 dark:bg-gray-800 {menuClass}"
  >
    <slot />
  </div>
{/if}

