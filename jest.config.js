const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    modulePathIgnorePatterns: ['<rootDir>/.localdevserver'],
    moduleNameMapper: {
        '^lightning/navigation$': '<rootDir>/flipswitch/core/test/jest-mocks/lightning/navigation',
        '^lightning/platformShowToastEvent$':
            '<rootDir>/flipswitch/core/test/jest-mocks/lightning/platformShowToastEvent',
    },
    testPathPattern: 'flipswitch/',
    testMatch: ['**/flipswitch/**/__tests__/**/*.test.js'],
};
