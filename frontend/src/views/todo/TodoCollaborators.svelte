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
            ].filter(user => user.email.includes(input));
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

<div class="todo-collaborators-panel p-4 bg-white shadow-lg rounded-lg">
    <button on:click={closeCollaboratorsPanel} class="float-right text-gray-500 hover:text-gray-700">X</button>
    <h2 class="text-2xl font-bold mb-4">Collaborators</h2>

    <h3 class="text-xl font-semibold mb-3">Current Collaborators</h3>
    {#if collaborators.length > 0}
        <ul class="space-y-2 mb-4">
            {#each collaborators as collaborator (collaborator.id)}
                <li class="flex items-center justify-between bg-gray-50 p-2 rounded-md">
                    <span>{collaborator.email}</span>
                    <button on:click={() => collaborator.id && handleRemoveCollaborator(collaborator.id)} class="text-red-500 hover:text-red-700 text-sm">Remove</button>
                </li>
            {/each}
        </ul>
    {:else}
        <p class="text-gray-600 mb-4">No collaborators yet.</p>
    {/if}

    <div class="mt-6 p-4 border rounded-md bg-gray-50">
        <h4 class="text-lg font-semibold mb-2">Add Collaborator</h4>
        <input
            type="text"
            bind:value={newCollaboratorEmail}
            on:input={handleSearchUsers}
            placeholder="Search by email"
            class="w-full p-2 border rounded-md mb-2"
        />
        {#if searchResults.length > 0}
            <ul class="border rounded-md bg-white mt-2 max-h-48 overflow-y-auto">
                {#each searchResults as user (user.id)}
                    <li class="flex items-center justify-between p-2 hover:bg-gray-100 cursor-pointer" on:click={() => user.id && handleAddCollaborator(user.id)}>
                        <span>{user.email}</span>
                        <button class="text-blue-500 hover:text-blue-700 text-sm">Add</button>
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