import { LightningElement, api } from 'lwc';

export default class BillingControlCenterKpiGrid extends LightningElement {
    @api tiles = [];
    @api compact = false;

    get normalizedTiles() {
        return (this.tiles || []).map((tile, index) => {
            const lines = Array.isArray(tile?.lines) ? tile.lines : [];
            const splitColumns = Array.isArray(tile?.splitColumns) ? tile.splitColumns : [];
            return {
                ...tile,
                key: tile?.key || `tile-${index}`,
                countText: tile?.countText || '',
                hint: tile?.hint || '',
                useSplit: splitColumns.length > 0,
                useLines: splitColumns.length === 0 && lines.length > 0,
                splitColumns,
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