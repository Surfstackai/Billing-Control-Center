const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

const LWC_ROOT = '<rootDir>/force-app/main/default/lwc';

module.exports = {
    ...jestConfig,
    moduleNameMapper: {
        ...jestConfig.moduleNameMapper,
        // CSS-only bundles are imported by other bundles' stylesheets. The default LWC
        // resolver only looks for a .js entry point, so point it at the stylesheet itself.
        '^c/billingControlCenterStyles$': `${LWC_ROOT}/billingControlCenterStyles/billingControlCenterStyles.css`
    },
    collectCoverageFrom: ['force-app/main/default/lwc/**/*.js', '!**/__tests__/**'],
    coverageDirectory: '<rootDir>/coverage/lwc'
};
