// Schedule the FlipSwitch daily expiration job
String cronExp = '0 0 0 * * ?'; // Daily at midnight
System.schedule('FlipSwitch Expiration Job', cronExp, new FeatureFlagExpirationJob());
System.debug('FlipSwitch expiration job scheduled.');
