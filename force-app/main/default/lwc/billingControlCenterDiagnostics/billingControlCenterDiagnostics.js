import { LightningElement, api } from 'lwc';

const DEFAULT_TITLE = 'Configuration warnings detected';

export default class BillingControlCenterDiagnostics extends LightningElement {
    @api warnings = [];
    @api title = DEFAULT_TITLE;
    @api isVisible = false;

    isExpanded = false;

    get normalizedWarnings() {
        return (this.warnings || [])
            .filter(warning => typeof warning === 'string' && warning.trim())
            .map((warning, index) => ({
                id: `${index}-${warning}`,
                message: warning
            }));
    }

    get shouldRender() {
        return this.isVisible && this.normalizedWarnings.length > 0;
    }

    get warningCountLabel() {
        const count = this.normalizedWarnings.length;
        return `${count} warning${count === 1 ? '' : 's'}`;
    }

    get toggleIconName() {
        return this.isExpanded ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get toggleLabel() {
        return this.isExpanded ? 'Hide details' : 'Show details';
    }

    handleToggle() {
        this.isExpanded = !this.isExpanded;
    }
}