<script lang="ts">
  import { onMount } from 'svelte';
  import { TodoViewModel } from '../../viewmodels/todo/TodoViewModel';
  import type { User } from '../../api/generated/models';
  import { createEventDispatcher } from 'svelte';

  export let listId: string;

  const dispatch = createEventDispatcher();
  const todoViewModel = new TodoViewModel();

  let collaborators: User[] = [];
  let newCollaboratorEmail: string = '';
  let searchResults: User[] = []; // For searching users to add

  onMount(async () => {
    await fetchCollaborators();
  });

  async function fetchCollaborators() {
    try {
      // TODO: Implement getCollaborators in TodoViewModel
      // For now, simulate fetching collaborators
      collaborators = [
        { id: 'user1', email: 'user1@example.com', createdAt: new Date(), updatedAt: new Date() },
        { id: 'user2', email: 'user2@example.com', createdAt: new Date(), updatedAt: new Date() },
      ];
    } catch (error) {
      console.error('Error fetching collaborators:', error);
    }
  }

  async function handleSearchUsers(event: Event) {
    const input = (event.target as HTMLInputElement).value;
    if (input.length < 3) {
      searchResults = [];
      return;
    }
    try {
      // TODO: Implement searchUsers in TodoViewModel (or a UserViewModel)
      // For now, simulate search results
      searchResults = [
        { id: 'user3', email: 'user3@example.com', createdAt: new Date(), updatedAt: new Date() },
        { id: 'user4', email: 'user4@example.com', createdAt: new Date(), updatedAt: new Date() },
      ].filter((user) => user.email.includes(input));
    } catch (error) {
      console.error('Error searching users:', error);
    }
  }

  async function handleAddCollaborator(userId: string) {
    try {
      // TODO: Implement addCollaborator in TodoViewModel
      console.log('Adding collaborator:', userId);
      await fetchCollaborators(); // Refresh list
      newCollaboratorEmail = '';
      searchResults = [];
    } catch (error) {
      console.error('Error adding collaborator:', error);
    }
  }

  async function handleRemoveCollaborator(userId: string) {
    try {
      // TODO: Implement removeCollaborator in TodoViewModel
      console.log('Removing collaborator:', userId);
      await fetchCollaborators(); // Refresh list
    } catch (error) {
      console.error('Error removing collaborator:', error);
    }
  }

  function closeCollaboratorsPanel() {
    dispatch('close');
  }
</script>

<div class="todo-collaborators-panel rounded-lg bg-white p-4 shadow-lg">
  <button on:click={closeCollaboratorsPanel} class="float-right text-gray-500 hover:text-gray-700"
    >X</button
  >
  <h2 class="mb-4 text-2xl font-bold">Collaborators</h2>

  <h3 class="mb-3 text-xl font-semibold">Current Collaborators</h3>
  {#if collaborators.length > 0}
    <ul class="mb-4 space-y-2">
      {#each collaborators as collaborator (collaborator.id)}
        <li class="flex items-center justify-between rounded-md bg-gray-50 p-2">
          <span>{collaborator.email}</span>
          <button
            on:click={() => collaborator.id && handleRemoveCollaborator(collaborator.id)}
            class="text-sm text-red-500 hover:text-red-700">Remove</button
          >
        </li>
      {/each}
    </ul>
  {:else}
    <p class="mb-4 text-gray-600">No collaborators yet.</p>
  {/if}

  <div class="mt-6 rounded-md border bg-gray-50 p-4">
    <h4 class="mb-2 text-lg font-semibold">Add Collaborator</h4>
    <input
      type="text"
      bind:value={newCollaboratorEmail}
      on:input={handleSearchUsers}
      placeholder="Search by email"
      class="mb-2 w-full rounded-md border p-2"
    />
    {#if searchResults.length > 0}
      <ul class="mt-2 max-h-48 overflow-y-auto rounded-md border bg-white">
        {#each searchResults as user (user.id)}
          <li
            class="flex cursor-pointer items-center justify-between p-2 hover:bg-gray-100"
            on:click={() => user.id && handleAddCollaborator(user.id)}
          >
            <span>{user.email}</span>
            <button class="text-sm text-blue-500 hover:text-blue-700">Add</button>
          </li>
        {/each}
      </ul>
    {/if}
  </div>
</div>

<style>
  .todo-collaborators-panel {
    max-width: 600px;
    margin: 0 auto;
  }
</style>
