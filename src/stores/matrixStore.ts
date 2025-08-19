import { writable, get } from 'svelte/store';
import * as sdk from 'matrix-js-sdk';

// --- Types ---
type ConnectionStatus = 'DISCONNECTED' | 'CONNECTING' | 'CONNECTED' | 'ERROR';

// --- Stores ---
export const connectionStatus = writable<ConnectionStatus>('DISCONNECTED');
export const matrixClient = writable<sdk.MatrixClient | null>(null);
export const roomList = writable<sdk.Room[]>([]);
export const currentRoomId = writable<string | null>(null);
export const messageList = writable<sdk.MatrixEvent[]>([]);

// --- Constants ---
const HOMESERVER_URL = 'https://beeper.com'; // Placeholder, needs to be confirmed by user

// --- Actions ---

/**
 * Initializes the Matrix client, logs in, and sets up event listeners.
 * @param {string} userId - The full Matrix user ID (e.g., '@username:beeper.com')
 * @param {string} password - The user's password.
 */
export async function login(userId, password) {
  connectionStatus.set('CONNECTING');

  try {
    const client = sdk.createClient({
      baseUrl: HOMESERVER_URL,
    });

    await client.loginWithPassword(userId, password);

    matrixClient.set(client);
    connectionStatus.set('CONNECTED');

    await client.startClient({ initialSyncLimit: 10 });

    // --- Set up event listeners ---

    // Populate initial room list and listen for updates
    const updateRooms = () => {
      const rooms = client.getRooms()
        .sort((a, b) => b.getLastLiveEvent().getTs() - a.getLastLiveEvent().getTs());
      roomList.set(rooms);
    };

    client.on('sync', (state, prevState, res) => {
      // 'PREPARED' is emitted when the initial sync is complete
      if (state === 'PREPARED') {
        updateRooms();
      }
    });

    // Listen for new messages in any room
    client.on('Room.timeline', (event, room, toStartOfTimeline) => {
      if (toStartOfTimeline) {
        return; // Don't add old messages that are fetched on scroll
      }
      // If the message is for the currently selected room, update the message list
      if (room.roomId === get(currentRoomId)) {
        messageList.update(messages => [...messages, event]);
      }
      // A new message in any room should update the room list order
      updateRooms();
    });

    updateRooms(); // Initial population

  } catch (error) {
    console.error('Matrix login failed:', error);
    connectionStatus.set('ERROR');
    matrixClient.set(null);
  }
}

/**
 * Sets the currently active room and loads its message timeline.
 * @param {string} roomId - The ID of the room to select.
 */
export function selectRoom(roomId: string) {
  const client = get(matrixClient);
  if (!client) return;

  const room = client.getRoom(roomId);
  if (!room) {
    console.error(`Room with ID ${roomId} not found.`);
    return;
  }

  currentRoomId.set(roomId);
  messageList.set(room.getLiveTimeline().getEvents());
}

/**
 * Logs out the current user and stops the client.
 */
export async function logout() {
  const client = get(matrixClient);
  if (client) {
    await client.logout();
    client.stopClient();
  }
  matrixClient.set(null);
  connectionStatus.set('DISCONNECTED');
  roomList.set([]);
  messageList.set([]);
  currentRoomId.set(null);
}
