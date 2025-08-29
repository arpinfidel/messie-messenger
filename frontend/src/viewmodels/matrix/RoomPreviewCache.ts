export type RoomPreview = {
  id: string;
  title: string;
  description: string;
  timestamp: number;
};

const KEY = 'mx.previews.v1';

export class RoomPreviewCache {
  load(): RoomPreview[] {
    try {
      return JSON.parse(localStorage.getItem(KEY) || '[]');
    } catch {
      return [];
    }
  }

  save(previews: RoomPreview[]) {
    localStorage.setItem(KEY, JSON.stringify(previews.slice(0, 200)));
  }
}
