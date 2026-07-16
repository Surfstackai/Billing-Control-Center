import { LightningElement, api } from 'lwc';

export default class BillingControlCenterKpiGrid extends LightningElement {
    @api tiles = [];

    get normalizedTiles() {
        return (this.tiles || []).map((tile, index) => ({
            ...tile,
            key: tile?.key || `tile-${index}`,
            countText: tile?.countText || '',
            hint: tile?.hint || ''
        }));
    }

    get gridStyle() {
        return `--bcc-kpi-columns: ${Math.max(this.normalizedTiles.length, 1)}`;
    }
}