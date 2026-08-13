import { LightningElement, api } from 'lwc';

export default class BillingControlCenterKpiGrid extends LightningElement {
    @api tiles = [];
    @api compact = false;

    get normalizedTiles() {
        return (this.tiles || []).map((tile, index) => {
            const lines = Array.isArray(tile?.lines) ? tile.lines : [];
            return {
                ...tile,
                key: tile?.key || `tile-${index}`,
                countText: tile?.countText || '',
                hint: tile?.hint || '',
                useLines: lines.length > 0,
                lines
            };
        });
    }

    get gridClass() {
        return this.compact ? 'kpi-grid kpi-grid_compact' : 'kpi-grid';
    }

    get gridStyle() {
        return `--bcc-kpi-columns: ${Math.max(this.normalizedTiles.length, 1)}`;
    }
}