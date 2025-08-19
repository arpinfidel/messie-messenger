<script lang="ts">
  // NOTE: This file contains placeholder routing logic. It will not function
  // until the environment's `npm install` issue is resolved, which currently
  // prevents routing libraries from being properly installed and imported.

  import { Router, Route } from "svelte-routing";

  // Import page components
  import Home from "./routes/index.svelte";
  import ChatRoom from "./routes/chat/[roomId].svelte";
  import Notes from "./routes/notes.svelte";
  import Todo from "./routes/todo.svelte";
  import Calendar from "./routes/calendar.svelte";
  import Email from "./routes/email.svelte";

  // The main App component will eventually hold the global layout,
  // including the unified sidebar and the main content area.
</script>

<!--
  This main layout would typically include the sidebar and other global UI.
  The <Router> would be placed in the main content area.
-->
<main>
  <!--
    The Router component renders the correct page based on the current URL.
    This configuration maps each URL path to its corresponding page component.
  -->
  <Router>
    <Route path="/" component="{Home}" />
    <Route path="/chat/:roomId" component="{ChatRoom}" />
    <Route path="/notes" component="{Notes}" />
    <Route path="/todo" component="{Todo}" />
    <Route path="/calendar" component="{Calendar}" />
    <Route path="/email" component="{Email}" />
  </Router>
</main>

<style>
  /* Basic global styling */
  :global(body) {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen,
      Ubuntu, Cantarell, 'Open Sans', 'Helvetica Neue', sans-serif;
    background-color: #f0f2f5;
  }

  main {
    display: flex;
    flex-direction: column;
    width: 100%;
    height: 100vh;
  }
</style>
