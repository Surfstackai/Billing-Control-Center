export const MIN_COLUMN_WIDTH = 80;
export const ORDERS_COLUMN_WIDTHS_KEY = 'bcc.columnWidths.orders';
export const INVOICING_COLUMN_WIDTHS_KEY = 'bcc.columnWidths.invoicing';
export const RECEIVABLES_COLUMN_WIDTHS_KEY = 'bcc.columnWidths.receivables';

export function loadColumnWidths(storageKey) {
    try {
        const rawValue = window.localStorage.getItem(storageKey);
        if (!rawValue) {
            return {};
        }
        const parsedValue = JSON.parse(rawValue);
        return parsedValue && typeof parsedValue === 'object' ? parsedValue : {};
    } catch (error) {
        return {};
    }
}

export function saveColumnWidths(storageKey, widths) {
    try {
        window.localStorage.setItem(storageKey, JSON.stringify(widths || {}));
    } catch (error) {
        // Ignore quota / private-mode failures.
    }
}

export function columnWidthStyle(width) {
    return width ? `width: ${width}px;` : null;
}
