// Split IndexedDbCache into a small façade delegating to per-store classes.
import { DbConnection } from './idb/DbConnection';
import { RoomsStore } from './idb/RoomsStore';
import { MetaStore } from './idb/MetaStore';
import { UsersStore } from './idb/UsersStore';
import { MediaStore } from './idb/MediaStore';
import { TimelineStore } from './idb/TimelineStore';
import { MembersStore } from './idb/MembersStore';

export class IndexedDbCache {
  private readonly conn = new DbConnection();
  private readonly meta = new MetaStore(this.conn);
  private readonly media = new MediaStore(this.conn);
  private readonly membersStore = new MembersStore(this.conn);

  readonly rooms = new RoomsStore(this.conn);
  readonly users = new UsersStore(this.conn);
  readonly timelines = new TimelineStore(this.conn);
  readonly members = this.membersStore;

  // Connection lifecycle
  init(): Promise<void> {
    return this.conn.init();
  }

  // Meta
  setMeta(key: string, value: any): Promise<void> {
    return this.meta.setMeta(key, value);
  }
  getMeta<T = any>(key: string): Promise<T | undefined> {
    return this.meta.getMeta<T>(key);
  }
  // Media
  putMedia(rec: {
    status: number;
    key: string;
    ts: number;
    bytes: number;
    mime: string;
    blob: Blob;
  }): Promise<void> {
    return this.media.putMedia(rec);
  }
  getMedia(
    key: string
  ): Promise<
    { status: number; key: string; ts: number; bytes: number; mime: string; blob: Blob } | undefined
  > {
    return this.media.getMedia(key);
  }
  deleteMedia(key: string): Promise<void> {
    return this.media.deleteMedia(key);
  }
  pruneMedia(maxEntries: number): Promise<void> {
    return this.media.pruneMedia(maxEntries);
  }
}
