import type { Readable } from 'svelte/store';
import type { TimelineItem } from '../../models/shared/TimelineItem';

// frontend/src/lib/matrix/IModuleViewModel.ts

/**
 * @interface IModuleViewModel
 * @description Defines a generalizable interface for module ViewModels.
 *              This interface ensures consistency across different communication modules
 *              (e.g., Matrix, Email, Calendar) for integration with the unified timeline
 *              and settings page.
 */
export interface IModuleViewModel {
    /**
     * @method initialize
     * @description Initializes the module ViewModel.
     * @returns {Promise<void>}
     */
    initialize(): Promise<void>;

    /**
     * @method getTimelineItems
     * @description Retrieves a list of timeline items for the module.
     * @returns {Writable<IMatrixTimelineItem[]>} A writable store containing an array of timeline item objects.
     */
    getTimelineItems(): Readable<TimelineItem[]>;

    /**
     * @method getSettingsComponent
     * @description Returns the Svelte component for the module's settings.
     * @returns {Object} A Svelte component.
     */
    getSettingsComponent(): any; // Using 'any' for now, as Svelte component types can be complex

    /**
     * @method getModuleName
     * @description Returns the name of the module.
     * @returns {string} The module name.
     */
    getModuleName(): string;

    // Add other common methods as identified during architectural design
}