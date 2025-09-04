export interface MatrixMessage {
  id: string;
  sender: string;
  senderDisplayName: string;
  senderAvatarUrl?: string;
  description: string;
  timestamp: number;
  isSelf: boolean;
  msgtype?: string;
  imageUrl?: string;
  mxcUrl?: string;
}

