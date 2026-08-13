import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import hasBillingControlCenterAdminAccess from '@salesforce/customPermission/Billing_Control_Center_Admin_Access';

import getTabs from '@salesforce/apex/BillingControl_ConfigService.getTabs';

const GROUP_BILLING = 'Billing';
const GROUP_STANDARD = 'Standard';
const GROUP_ADMIN = 'Admin';
const TARGET_INTERNAL_TAB = 'Internal BCC Tab';
const TARGET_OBJECT_HOME = 'Object Home';
const TARGET_APP = 'App';
const TARGET_URL = 'URL';

const SUPPORTED_INTERNAL_TABS = new Set(['ORDERS', 'INVOICING', 'RECEIVABLES']);

const DEFAULT_INTERNAL_ITEMS = [
    { developerKey: 'ORDERS', label: 'Work Order Ledger' },
    { developerKey: 'INVOICING', label: 'Invoicing' },
    { developerKey: 'RECEIVABLES', label: 'Receivables' }
];

const DEFAULT_ICONS = {
    ORDERS: 'utility:table',
    INVOICING: 'utility:money',
    RECEIVABLES: 'utility:chart',
    OPPORTUNITIES: 'utility:opportunity',
    WORK_ORDERS: 'utility:work_order_type',
    SERVICE_APPOINTMENTS: 'utility:event',
    REPORTS: 'utility:report',
    SETTINGS: 'utility:settings'
};

function normalizeKey(value) {
    return value ? String(value).trim().toUpperCase() : '';
}

function getDefaultNavItems() {
    return DEFAULT_INTERNAL_ITEMS.map((item, index) => ({
        ...item,
        displayOrder: (index + 1) * 10,
        navigationGroup: GROUP_BILLING,
        navigationTargetType: TARGET_INTERNAL_TAB,
        iconName: DEFAULT_ICONS[item.developerKey] || 'utility:apps'
    }));
}

export default class BillingControlCenterShell extends NavigationMixin(LightningElement) {
    billingNavItems = [];
    standardNavItems = [];
    adminNavItems = [];
    activeTabKey = 'ORDERS';
    isSidebarCollapsed = false;

    connectedCallback() {
        this.loadShellConfig();
    }

    get isOrdersActive() {
        return this.activeTabKey === 'ORDERS';
    }

    get isInvoicingActive() {
        return this.activeTabKey === 'INVOICING';
    }

    get isReceivablesActive() {
        return this.activeTabKey === 'RECEIVABLES';
    }

    get hasAdminItems() {
        return this.adminNavItems.length > 0;
    }

    get hasStandardItems() {
        return this.standardNavItems.length > 0;
    }

    get shellClass() {
        return `bcc-shell${this.isSidebarCollapsed ? ' bcc-shell_collapsed' : ''}`;
    }

    get sidebarClass() {
        return `bcc-shell__sidebar${this.isSidebarCollapsed ? ' bcc-shell__sidebar_collapsed' : ''}`;
    }

    get toggleIconName() {
        return this.isSidebarCollapsed ? 'utility:chevronright' : 'utility:chevronleft';
    }

    get toggleAlternativeText() {
        return this.isSidebarCollapsed ? 'Expand navigation' : 'Collapse navigation';
    }

    async loadShellConfig() {
        try {
            const tabs = await getTabs();
            const groupedItems = this.buildNavigationGroups(tabs || []);
            const activeKey = this.resolveInitialActiveKey(groupedItems.billing);

            if (groupedItems.billing.length === 0) {
                this.applyFallbackNavigation();
                return;
            }

            this.activeTabKey = activeKey;
            this.billingNavItems = this.decorateNavItems(groupedItems.billing, true);
            this.standardNavItems = groupedItems.standard;
            this.adminNavItems = groupedItems.admin;
        } catch (error) {
            console.warn(
                'Failed to load Billing Control Center shell config. Using fallback navigation.',
                error
            );
            this.applyFallbackNavigation();
        }
    }

    buildNavigationGroups(tabConfigs) {
        const billing = [];
        const standard = [];
        const admin = [];

        (tabConfigs || []).forEach(record => {
            if (!record?.showInNavigation) {
                return;
            }

            const developerKey = normalizeKey(record.developerKey);
            if (!developerKey) {
                return;
            }

            const requiredCustomPermission = record.requiredCustomPermission;
            if (
                requiredCustomPermission === 'Billing_Control_Center_Admin_Access' &&
                !hasBillingControlCenterAdminAccess
            ) {
                return;
            }

            const item = {
                developerKey,
                label: record.label || developerKey,
                iconName: record.iconName || DEFAULT_ICONS[developerKey] || 'utility:apps',
                displayOrder: Number(record.displayOrder || 0),
                navigationGroup: record.navigationGroup || GROUP_BILLING,
                navigationTargetType: record.navigationTargetType || TARGET_INTERNAL_TAB,
                targetObjectApiName: record.targetObjectApiName,
                targetAppDeveloperName: record.targetAppDeveloperName,
                targetUrl: record.targetUrl
            };

            if (item.navigationGroup === GROUP_STANDARD) {
                standard.push(item);
            } else if (item.navigationGroup === GROUP_ADMIN) {
                admin.push(item);
            } else {
                billing.push(item);
            }
        });

        return {
            billing: this.decorateNavItems(billing, true),
            standard: this.decorateNavItems(standard, false),
            admin: this.decorateNavItems(admin, false)
        };
    }

    decorateNavItems(items, isBillingGroup) {
        return (items || []).map(item => ({
            ...item,
            isBillingGroup,
            buttonClass: this.buildNavButtonClass(item, isBillingGroup)
        }));
    }

    buildNavButtonClass(item, isBillingGroup) {
        const classes = ['bcc-nav__item'];
        if (isBillingGroup && item.developerKey === this.activeTabKey) {
            classes.push('bcc-nav__item_active');
        }
        return classes.join(' ');
    }

    resolveInitialActiveKey(billingItems) {
        const supportedBillingItems = (billingItems || []).filter(
            item =>
                item.navigationTargetType === TARGET_INTERNAL_TAB &&
                SUPPORTED_INTERNAL_TABS.has(item.developerKey)
        );

        if (supportedBillingItems.length === 0) {
            return 'ORDERS';
        }

        if (supportedBillingItems.some(item => item.developerKey === this.activeTabKey)) {
            return this.activeTabKey;
        }

        return supportedBillingItems[0].developerKey;
    }

    applyFallbackNavigation() {
        this.billingNavItems = this.decorateNavItems(getDefaultNavItems(), true);
        this.standardNavItems = [];
        this.adminNavItems = [];
        this.activeTabKey = 'ORDERS';
    }

    handleToggleSidebar() {
        this.isSidebarCollapsed = !this.isSidebarCollapsed;
    }

    async handleNavClick(event) {
        const developerKey = normalizeKey(event.currentTarget.dataset.key);
        const group = event.currentTarget.dataset.group;
        const item = this.findNavItem(group, developerKey);

        if (!item) {
            return;
        }

        if (item.navigationTargetType === TARGET_INTERNAL_TAB) {
            if (!SUPPORTED_INTERNAL_TABS.has(item.developerKey)) {
                console.warn(`Unsupported Billing Control Center tab in shell: ${item.developerKey}`);
                return;
            }

            this.activeTabKey = item.developerKey;
            this.billingNavItems = this.decorateNavItems(this.billingNavItems, true);
            return;
        }

        if (group === GROUP_STANDARD) {
            await this.openInNewTab(item);
            return;
        }

        if (item.navigationTargetType === TARGET_OBJECT_HOME && item.targetObjectApiName) {
            this[NavigationMixin.Navigate]({
                type: 'standard__objectPage',
                attributes: {
                    objectApiName: item.targetObjectApiName,
                    actionName: 'home'
                }
            });
            return;
        }

        if (item.navigationTargetType === TARGET_APP) {
            const appDeveloperName = item.targetAppDeveloperName || 'Billing_Control_Center_Config';
            const targetUrl = `/lightning/app/c__${appDeveloperName}`;
            this[NavigationMixin.Navigate]({
                type: 'standard__webPage',
                attributes: {
                    url: targetUrl
                }
            });
            return;
        }

        if (item.navigationTargetType === TARGET_URL && item.targetUrl) {
            this[NavigationMixin.Navigate]({
                type: 'standard__webPage',
                attributes: {
                    url: item.targetUrl
                }
            });
        }
    }

    async openInNewTab(item) {
        const newTab = window.open('', '_blank');

        if (!newTab) {
            return;
        }

        const url = await this.generateNavigationUrl(item);
        if (url) {
            newTab.location = url;
            return;
        }

        newTab.close();
    }

    async generateNavigationUrl(item) {
        if (item.navigationTargetType === TARGET_OBJECT_HOME && item.targetObjectApiName) {
            return this[NavigationMixin.GenerateUrl]({
                type: 'standard__objectPage',
                attributes: {
                    objectApiName: item.targetObjectApiName,
                    actionName: 'home'
                }
            });
        }

        if (item.navigationTargetType === TARGET_APP) {
            const appDeveloperName = item.targetAppDeveloperName || 'Billing_Control_Center_Config';
            return this[NavigationMixin.GenerateUrl]({
                type: 'standard__webPage',
                attributes: {
                    url: `/lightning/app/c__${appDeveloperName}`
                }
            });
        }

        if (item.navigationTargetType === TARGET_URL && item.targetUrl) {
            return this[NavigationMixin.GenerateUrl]({
                type: 'standard__webPage',
                attributes: {
                    url: item.targetUrl
                }
            });
        }

        return null;
    }

    findNavItem(group, developerKey) {
        const source =
            group === GROUP_STANDARD
                ? this.standardNavItems
                : group === GROUP_ADMIN
                  ? this.adminNavItems
                  : this.billingNavItems;
        return (source || []).find(item => item.developerKey === developerKey);
    }
}