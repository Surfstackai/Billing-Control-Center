export function accountGroupKey(row) {
    if (row?.accountId) {
        return String(row.accountId);
    }
    const name = (row?.accountName || '').trim().toLowerCase();
    return name || `__blank__${row?.rowKey || row?.key || ''}`;
}

export function compareAccountGroup(left, right, directionMultiplier = 1) {
    const leftName = (left?.accountName || '').trim();
    const rightName = (right?.accountName || '').trim();
    if (!leftName && !rightName) {
        return String(left?.accountId || '').localeCompare(String(right?.accountId || '')) * directionMultiplier;
    }
    if (!leftName) {
        return 1;
    }
    if (!rightName) {
        return -1;
    }
    const byName = leftName.localeCompare(rightName, undefined, {
        numeric: true,
        sensitivity: 'base'
    });
    if (byName !== 0) {
        return byName * directionMultiplier;
    }
    return String(left?.accountId || '').localeCompare(String(right?.accountId || '')) * directionMultiplier;
}

export function isAccountSortField(fieldName) {
    return fieldName === 'accountUrl' || fieldName === 'accountName';
}

export function sortRowsWithAccountGroup(rows, fieldName, direction, compareRowValues) {
    const directionMultiplier = direction === 'desc' ? -1 : 1;
    const accountMultiplier = isAccountSortField(fieldName) ? directionMultiplier : 1;
    const columnMultiplier = isAccountSortField(fieldName) ? 1 : directionMultiplier;
    return [...(rows || [])].sort((left, right) => {
        const accountCompare = compareAccountGroup(left, right, accountMultiplier);
        if (accountCompare !== 0) {
            return accountCompare;
        }
        const primary = compareRowValues(left, right, fieldName, columnMultiplier);
        if (primary !== 0) {
            return primary;
        }
        const tieLeft = left?.rowKey != null ? String(left.rowKey) : String(left?.key || '');
        const tieRight = right?.rowKey != null ? String(right.rowKey) : String(right?.key || '');
        return tieLeft.localeCompare(tieRight) * columnMultiplier;
    });
}

export function decorateAccountGroups(rows, rowClassBase = 'slds-hint-parent grouped-diary-table__row') {
    let previousKey = null;
    return (rows || []).map(row => {
        const key = accountGroupKey(row);
        const isAccountGroupStart = key !== previousKey;
        previousKey = key;
        const groupClass = isAccountGroupStart
            ? ' grouped-diary-table__row--account-start'
            : ' grouped-diary-table__row--account-continue';
        return {
            ...row,
            isAccountGroupStart,
            showAccountName: isAccountGroupStart,
            rowClass: `${rowClassBase}${groupClass}`
        };
    });
}
