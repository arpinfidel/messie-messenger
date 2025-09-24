import * as matrixSdk from 'matrix-js-sdk';
import { PushRuleActionName, type IPushRule } from 'matrix-js-sdk/lib/@types/PushRules';
import type { ClientGetter } from './MatrixClientManager';

export class MatrixPushRuleService {
  private pushRulesInitPromise: Promise<void> | null = null;
  private mutedRooms = new Map<string, boolean>();

  constructor(private readonly getClient: ClientGetter) {}

  async ensurePushRulesLoaded(): Promise<void> {
    const client = this.requireClient();
    if (client.pushRules) {
      return;
    }

    if (!this.pushRulesInitPromise) {
      this.pushRulesInitPromise = client
        .getPushRules()
        .then((rules) => {
          client.setPushRules(rules);
        })
        .catch((err) => {
          console.warn('[MatrixPushRuleService] Failed to load push rules', err);
          throw err;
        })
        .finally(() => {
          this.pushRulesInitPromise = null;
        });
    }

    await this.pushRulesInitPromise;
  }

  async isRoomMuted(roomId: string): Promise<boolean> {
    if (!roomId) return false;
    if (this.mutedRooms.has(roomId)) {
      return this.mutedRooms.get(roomId)!;
    }
    return this.refreshRoomMuteState(roomId);
  }

  async refreshRoomMuteState(roomId: string): Promise<boolean> {
    if (!roomId) return false;
    const client = this.requireClient();
    await this.ensurePushRulesLoaded();
    const rule = client.getRoomPushRule('global', roomId);
    const muted = this.isMuteRule(rule);
    this.mutedRooms.set(roomId, muted);
    return muted;
  }

  async setRoomMuted(roomId: string, mute: boolean): Promise<boolean> {
    if (!roomId) return false;
    const client = this.requireClient();
    await this.ensurePushRulesLoaded();
    await client.setRoomMutePushRule('global', roomId, mute);
    this.mutedRooms.set(roomId, mute);
    void this.refreshRoomMuteState(roomId).catch((err) => {
      console.warn('[MatrixPushRuleService] Failed to verify mute state after update', err);
    });
    return mute;
  }

  private requireClient(): matrixSdk.MatrixClient {
    const client = this.getClient();
    if (!client) {
      throw new Error('Matrix client not initialized.');
    }
    return client;
  }

  private isMuteRule(rule: IPushRule | undefined): boolean {
    if (!rule) return false;
    if (rule.enabled === false) return false;
    return rule.actions.some(
      (action) => typeof action === 'string' && action === PushRuleActionName.DontNotify
    );
  }
}
