trigger FeatureFlagEvaluationTrigger on Feature_Flag_Evaluation__e (after insert) {
    FeatureFlagEvaluationTriggerHandler.handleEvaluationEvents(Trigger.new);
}
