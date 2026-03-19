/**
 * @description Custom exception type for the FlipSwitch framework.
 *              Thrown internally; callers are protected by the circuit breaker
 *              in FeatureFlagEvaluator and never see this exception directly.
 */
public inherited sharing class FeatureFlagException extends Exception {}
