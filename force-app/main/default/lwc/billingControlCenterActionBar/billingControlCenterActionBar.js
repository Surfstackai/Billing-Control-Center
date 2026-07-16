import { LightningElement, api } from 'lwc';

export default class BillingControlCenterActionBar extends LightningElement {
    @api actions = [];

    get normalizedActions() {
        return (this.actions || []).map((action, index) => ({
            ...action,
            key: action?.key || `action-${index}`,
            variant: action?.variant || 'neutral'
        }));
    }

    handleActionClick(event) {
        const key = event.currentTarget.dataset.key;
        const action = this.normalizedActions.find(item => item.key === key);
        this.dispatchEvent(
            new CustomEvent('actionclick', {
                detail: { key, action }
            })
        );
    }
}