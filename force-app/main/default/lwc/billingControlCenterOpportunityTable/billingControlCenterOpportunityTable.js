import { LightningElement, api } from 'lwc';

export default class BillingControlCenterOpportunityTable extends LightningElement {
    _opportunityGroups = [];
    _selectedOpportunityIds = [];
    displayedGroups = [];

    @api emptyMessage = 'No records found.';
    @api tableLabel = 'Service appointments grouped by opportunity';

    @api
    set opportunityGroups(value) {
        this._opportunityGroups = (value || []).map(group => ({
            ...group,
            rows: (group.rows || []).map(row => ({ ...row }))
        }));
        this.pruneState();
        this.rebuildGroups();
    }

    get opportunityGroups() {
        return this._opportunityGroups;
    }

    @api
    set selectedOpportunityIds(value) {
        this._selectedOpportunityIds = Array.isArray(value) ? [...value] : [];
        this.pruneState();
        this.rebuildGroups();
    }

    get selectedOpportunityIds() {
        return this._selectedOpportunityIds;
    }

    get hasRows() {
        return this.totalRowCount > 0;
    }

    get totalRowCount() {
        return this._opportunityGroups.reduce((sum, group) => sum + (group.rows || []).length, 0);
    }

    get groupColumnSpan() {
        return 5;
    }

    handleOpportunitySelection(event) {
        const opportunityId = event.target.dataset.opportunityId;
        if (!opportunityId) {
            return;
        }

        const selected = new Set(this.selectedOpportunityIds);
        if (event.target.checked) {
            selected.add(opportunityId);
        } else {
            selected.delete(opportunityId);
        }

        this._selectedOpportunityIds = Array.from(selected);
        this.rebuildGroups();
        this.notifySelectionChange([opportunityId], event.target.checked);
    }

    pruneState() {
        const visibleIds = new Set(this.getAllOpportunityIds());
        this._selectedOpportunityIds = (this._selectedOpportunityIds || []).filter(
            opportunityId => visibleIds.has(opportunityId)
        );
    }

    rebuildGroups() {
        const selectedIds = new Set(this.selectedOpportunityIds);

        this.displayedGroups = (this._opportunityGroups || []).map(group => {
            const opportunityId = group.opportunityId;
            const accountId = group.accountId;

            const rows = (group.rows || [])
                .map(row => ({
                    ...row,
                    opportunityId: row.opportunityId || opportunityId,
                    opportunityName: row.opportunityName || group.opportunityName,
                    opportunityAmount:
                        row.opportunityAmount !== null && row.opportunityAmount !== undefined
                            ? row.opportunityAmount
                            : group.opportunityAmount,
                    accountId: row.accountId || accountId,
                    accountName: row.accountName || group.accountName
                }))
                .sort((left, right) => this.compareByCompletion(left, right))
                .map(row => {
                    const effectiveOpportunityId = row.opportunityId || opportunityId;
                    return {
                        ...row,
                        key: `${effectiveOpportunityId || 'NO_OPP'}-${row.serviceAppointmentId}`,
                        hasWorkOrder: !!row.workOrderId,
                        serviceAppointmentUrl: row.serviceAppointmentId
                            ? `/lightning/r/ServiceAppointment/${row.serviceAppointmentId}/view`
                            : null,
                        workOrderUrl: row.workOrderId ? `/lightning/r/WorkOrder/${row.workOrderId}/view` : null
                    };
                });

            const effectiveOpportunityId = opportunityId || (rows.length > 0 ? rows[0].opportunityId : null);
            const effectiveAccountId = accountId || (rows.length > 0 ? rows[0].accountId : null);

            return {
                ...group,
                opportunityId: effectiveOpportunityId,
                groupKey: `OPP-${effectiveOpportunityId || 'NO_OPP'}`,
                rowCount: rows.length,
                rows,
                hasOpportunity: !!effectiveOpportunityId,
                hasAccount: !!effectiveAccountId,
                isSelectable: !!effectiveOpportunityId,
                isNotSelectable: !effectiveOpportunityId,
                isSelected: !!effectiveOpportunityId && selectedIds.has(effectiveOpportunityId),
                selectLabel: `Select opportunity ${group.opportunityName || effectiveOpportunityId || ''}`,
                opportunityUrl: effectiveOpportunityId ? `/lightning/r/Opportunity/${effectiveOpportunityId}/view` : null,
                accountUrl: effectiveAccountId ? `/lightning/r/Account/${effectiveAccountId}/view` : null,
                displayOpportunityAmount:
                    group.opportunityAmount !== null && group.opportunityAmount !== undefined
                        ? group.opportunityAmount
                        : rows.length > 0
                            ? rows[0].opportunityAmount
                            : null
            };
        });
    }

    notifySelectionChange(changedOpportunityIds = [], checked = false) {
        this.dispatchEvent(
            new CustomEvent('selectionchange', {
                detail: {
                    selectedOpportunityIds: [...this.selectedOpportunityIds],
                    selectedCount: this.selectedOpportunityIds.length,
                    changedOpportunityIds,
                    checked
                }
            })
        );
    }

    getAllOpportunityIds() {
        const opportunityIds = new Set();
        for (const group of this._opportunityGroups) {
            const effectiveOpportunityId = group.opportunityId
                || ((group.rows || []).length > 0 ? group.rows[0].opportunityId : null);
            if (effectiveOpportunityId) {
                opportunityIds.add(effectiveOpportunityId);
            }
        }
        return Array.from(opportunityIds);
    }

    compareByCompletion(left, right) {
        const leftDate = left && left.completionDateTime ? Date.parse(left.completionDateTime) : NaN;
        const rightDate = right && right.completionDateTime ? Date.parse(right.completionDateTime) : NaN;

        if (Number.isNaN(leftDate) && Number.isNaN(rightDate)) {
            return this.compareText(
                left ? left.serviceAppointmentNumber : null,
                right ? right.serviceAppointmentNumber : null
            );
        }
        if (Number.isNaN(leftDate)) {
            return 1;
        }
        if (Number.isNaN(rightDate)) {
            return -1;
        }
        if (leftDate !== rightDate) {
            return rightDate - leftDate;
        }
        return this.compareText(
            left ? left.serviceAppointmentNumber : null,
            right ? right.serviceAppointmentNumber : null
        );
    }

    compareText(leftValue, rightValue) {
        const leftText = leftValue ? String(leftValue) : '';
        const rightText = rightValue ? String(rightValue) : '';
        return leftText.localeCompare(rightText, undefined, { numeric: true, sensitivity: 'base' });
    }
}