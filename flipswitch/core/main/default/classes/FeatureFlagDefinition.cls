/**
 * @description Fluent builder for declaring feature flag metadata inline.
 *              Returned by FeatureFlag.define(). Allows developers to self-document
 *              flag purpose, type, and defaults directly in code. The flag is
 *              auto-registered in the FlipSwitch_Flag_Registry__c so the admin
 *              dashboard discovers it without a metadata deployment.
 *
 *              Idempotent — safe to call every transaction (e.g. in a static
 *              initializer or at the top of a service method). Existing records
 *              are never overwritten; only null/blank fields are filled.
 *
 *              Usage:
 *              FeatureFlag.define('NEW_CHECKOUT')
 *                  .type('Boolean')
 *                  .defaultValue('false')
 *                  .category('Checkout')
 *                  .description('Enables the redesigned checkout flow')
 *                  .register();
 *
 *              // Then evaluate normally:
 *              if (FeatureFlag.isEnabled('NEW_CHECKOUT')) { ... }
 */
public inherited sharing class FeatureFlagDefinition {

    private final String flagKey;
    private String flagType;
    private String flagDefaultValue;
    private String flagCategory;
    private String flagDescription;
    private Date flagExpirationDate;

    /**
     * @description Internal constructor. Use FeatureFlag.define(flagKey) to create.
     * @param flagKey  Unique flag identifier (DeveloperName convention)
     */
    public FeatureFlagDefinition(String flagKey) {
        this.flagKey = flagKey;
    }

    // ─── Fluent configuration methods ─────────────────────────────────────

    /**
     * @description Set the flag type.
     * @param type  'Boolean' | 'Variant' | 'Percentage' (default: Boolean)
     * @return      This definition builder for chaining
     */
    public FeatureFlagDefinition type(String type) {
        this.flagType = type;
        return this;
    }

    /**
     * @description Set the default value when no targeting rules match.
     * @param value  For Boolean: 'true'/'false'. For Variant: default variant key.
     *               For Percentage: rollout percentage as string (e.g. '50').
     * @return       This definition builder for chaining
     */
    public FeatureFlagDefinition defaultValue(String value) {
        this.flagDefaultValue = value;
        return this;
    }

    /**
     * @description Set the dashboard category for grouping.
     * @param category  Human-readable label (e.g. 'Checkout', 'UI', 'Backend')
     * @return          This definition builder for chaining
     */
    public FeatureFlagDefinition category(String category) {
        this.flagCategory = category;
        return this;
    }

    /**
     * @description Set the flag description. Explain the purpose and owner.
     * @param description  Free-text description shown in the admin dashboard
     * @return             This definition builder for chaining
     */
    public FeatureFlagDefinition description(String description) {
        this.flagDescription = description;
        return this;
    }

    /**
     * @description Set an auto-expiration date. The flag will be treated as
     *              disabled after this date.
     * @param expirationDate  Date after which the flag expires (null = never)
     * @return                This definition builder for chaining
     */
    public FeatureFlagDefinition expiresOn(Date expirationDate) {
        this.flagExpirationDate = expirationDate;
        return this;
    }

    // ─── Terminal method ──────────────────────────────────────────────────

    /**
     * @description Register the flag in the FlipSwitch_Flag_Registry__c.
     *              Idempotent — safe to call every transaction. Existing records
     *              are updated only for fields that are currently null/blank
     *              (fill-not-overwrite), so admin dashboard edits are preserved.
     */
    public void register() {
        FeatureFlagRegistry.registerWithMetadata(
            flagKey,
            flagType,
            flagDefaultValue,
            flagCategory,
            flagDescription,
            flagExpirationDate
        );
    }
}
