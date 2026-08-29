import { LightningElement, api } from 'lwc';

export default class BillingControlCenterKpiGrid extends LightningElement {
    @api tiles = [];
    @api compact = false;
    @api selectedKey;

    get normalizedTiles() {
        return (this.tiles || []).map((tile, index) => {
            const lines = Array.isArray(tile?.lines) ? tile.lines : [];
            const splitColumns = Array.isArray(tile?.splitColumns) ? tile.splitColumns : [];
            const key = tile?.key || `tile-${index}`;
            const developerKey = tile?.developerKey || key;
            const isSelected =
                Boolean(this.selectedKey) &&
                (this.selectedKey === key || this.selectedKey === developerKey);
            return {
                ...tile,
                key,
                developerKey,
                countText: tile?.countText || '',
                hint: tile?.hint || '',
                useSplit: splitColumns.length > 0,
                useLines: splitColumns.length === 0 && lines.length > 0,
                splitColumns,
                lines,
                tileClass: `kpi-tile${isSelected ? ' kpi-tile_selected' : ''}`,
                ariaPressed: isSelected ? 'true' : 'false'
            };
        });
    }

    get gridClass() {
        return this.compact ? 'kpi-grid kpi-grid_compact' : 'kpi-grid';
    }

    get gridStyle() {
        return `--bcc-kpi-columns: ${Math.max(this.normalizedTiles.length, 1)}`;
    }

    handleTileClick(event) {
        const key = event.currentTarget.dataset.key;
        const developerKey = event.currentTarget.dataset.developerKey || key;
        this.dispatchEvent(
            new CustomEvent('tileclick', {
                detail: { key, developerKey }
            })
        );
    }
}
