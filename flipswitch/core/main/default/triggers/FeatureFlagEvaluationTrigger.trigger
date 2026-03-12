trigger FeatureFlagEvaluationTrigger on FlipSwitch_Evaluation__e (after insert) {
    FeatureFlagEvaluationTriggerHandler.handleEvaluationEvents(Trigger.new);
}
