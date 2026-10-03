/**
 * @description Demo class that registers code-defined feature flags using the
 *              FeatureFlag.define() API. Run the seed() method to populate
 *              the FlipSwitch_Flag_Registry__c with sample flags that will
 *              appear in the admin dashboard with source = 'Code'.
 *
 *              Execute via Anonymous Apex:
 *              FeatureFlagSeeder.seed();
 */
public with sharing class FeatureFlagSeeder {

    public static void seed() {

        // 1. Boolean flag — simple on/off toggle
        FeatureFlag.define('NEW_CHECKOUT_FLOW')
            .type('Boolean')
            .defaultValue('false')
            .category('Checkout')
            .description('Enables the redesigned checkout experience with one-page layout')
            .register();

        // 2. Boolean flag — dark mode UI toggle
        FeatureFlag.define('DARK_MODE')
            .type('Boolean')
            .defaultValue('false')
            .category('UI')
            .description('Toggles dark mode theme across Lightning pages')
            .register();

        // 3. Percentage rollout — gradual release
        FeatureFlag.define('AI_RECOMMENDATIONS')
            .type('Percentage')
            .defaultValue('25')
            .category('AI')
            .description('AI-powered product recommendations — rolling out to 25% of users')
            .register();

        // 4. Percentage rollout — backend feature
        FeatureFlag.define('ASYNC_PROCESSING_V2')
            .type('Percentage')
            .defaultValue('50')
            .category('Backend')
            .description('Routes 50% of batch jobs through the new async processing engine')
            .register();

        // 5. Boolean flag with expiration — time-boxed experiment
        FeatureFlag.define('HOLIDAY_BANNER')
            .type('Boolean')
            .defaultValue('true')
            .category('Marketing')
            .description('Seasonal holiday promotional banner on the home page')
            .expiresOn(Date.today().addDays(14))
            .register();

        // 6. Minimal one-liner registration
        FeatureFlag.register('BETA_SEARCH');

        System.debug('FeatureFlagSeeder: 6 code-defined flags registered.');
    }
}
