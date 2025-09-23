export interface TimelineSourceFilterOption {
  id: string;
  label: string;
  /**
   * Item sources matched by this option. Empty array indicates no filtering.
   */
  sources: string[];
}

export interface MatrixBridgeConfig {
  /**
   * Stable identifier for the bridge. Used as part of filter/source IDs.
   */
  id: string;
  /** Human friendly label shown in the filter menu. */
  label: string;
  /**
   * Timeline source identifier emitted by Matrix timeline items when this
   * bridge participates in the room. Must be unique per bridge.
   */
  timelineSourceId: string;
  /**
   * Matrix user IDs that, when joined to a room, indicate it belongs to this bridge.
   */
  userIds: string[];
}

export const MATRIX_BRIDGES: MatrixBridgeConfig[] = [
  {
    id: 'linkedin',
    label: 'LinkedIn',
    timelineSourceId: 'matrix-bridge-linkedin',
    userIds: ['@linkedinbot:beeper.local'],
  },
  {
    id: 'whatsapp',
    label: 'WhatsApp',
    timelineSourceId: 'matrix-bridge-whatsapp',
    userIds: ['@whatsappbot:beeper.local'],
  },
];

const matrixBridgeUserIdEntries = MATRIX_BRIDGES.flatMap((bridge) =>
  bridge.userIds.map<[string, string]>((userId) => [userId, bridge.timelineSourceId])
);

const matrixBridgeSourceIds = MATRIX_BRIDGES.map((bridge) => bridge.timelineSourceId);
const legacyMatrixBridgeSourceId = 'matrix-bridge';

const matrixBridgeUserIdMap = new Map<string, string>(matrixBridgeUserIdEntries);

export const MATRIX_BRIDGE_USER_ID_TO_SOURCE: ReadonlyMap<string, string> = matrixBridgeUserIdMap;

export const MATRIX_BRIDGE_SOURCE_IDS: string[] = matrixBridgeSourceIds;

const matrixBridgeFilterOptions: TimelineSourceFilterOption[] = MATRIX_BRIDGES.map((bridge) => ({
  id: bridge.timelineSourceId,
  label: bridge.label,
  sources: [bridge.timelineSourceId],
}));

const timelineFilters: TimelineSourceFilterOption[] = [
  { id: 'all', label: 'All sources', sources: [] },
  {
    id: 'matrix',
    label: 'Matrix',
    sources: ['matrix', legacyMatrixBridgeSourceId, ...matrixBridgeSourceIds],
  },
  {
    id: 'matrix-bridge',
    label: 'Matrix Bridges',
    sources: [legacyMatrixBridgeSourceId, ...matrixBridgeSourceIds],
  },
  ...matrixBridgeFilterOptions,
  { id: 'email', label: 'Email', sources: ['email'] },
  { id: 'todo', label: 'Todo', sources: ['todo'] },
];

export const TIMELINE_SOURCE_FILTERS: TimelineSourceFilterOption[] = timelineFilters;

export const DEFAULT_TIMELINE_SOURCE_FILTER = 'all';
