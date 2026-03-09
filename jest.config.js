'use strict';

const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    modulePathIgnorePatterns: ['<rootDir>/.localdevserver'],
    collectCoverageFrom: ['force-app/main/default/lwc/**/*.js', '!force-app/main/default/lwc/**/__tests__/**'],
    coverageThreshold: {
        global: {
            lines: 80
        }
    }
};
