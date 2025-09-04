export interface LiteRoom {
  id: string;
  name: string;
}

export interface LiteMessage {
  id: string;
  roomId: string;
  sender: string;
  content: string;
  timestamp: number;
}

export interface LiteMember {
  userId: string;
  displayName: string;
  avatarUrl?: string;
}
