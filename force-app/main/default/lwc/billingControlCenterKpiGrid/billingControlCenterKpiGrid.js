import { LightningElement, api } from 'lwc';

export default class BillingControlCenterKpiGrid extends LightningElement {
    @api tiles = [];
    @api compact = false;

    get normalizedTiles() {
        return (this.tiles || []).map((tile, index) => ({
            ...tile,
            key: tile?.key || `tile-${index}`,
            countText: tile?.countText || '',
            hint: tile?.hint || ''
        }));
    }

    get gridClass() {
        return this.compact ? 'kpi-grid kpi-grid_compact' : 'kpi-grid';
    }

    get gridStyle() {
        return `--bcc-kpi-columns: ${Math.max(this.normalizedTiles.length, 1)}`;
    }
}