HttpRequest req = new HttpRequest();
req.setEndpoint(URL.getOrgDomainURL().toExternalForm() + '/services/data/v64.0/tooling/sobjects/FlexiPage');
req.setMethod('POST');
req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
req.setHeader('Content-Type', 'application/json');
req.setBody('{"FullName":"Test_Probe4","Metadata":{"description":"T","masterLabel":"T","type":"AppPage","template":{"name":"flexipage:defaultAppHomeTemplate"},"flexiPageRegions":[{"name":"Facet-randomId123","type":"Facet","itemInstances":[{"componentInstance":{"componentName":"forceContent:richTextEditor","identifier":"rt1"}}]}]}}');
HttpResponse res = new Http().send(req);
System.debug('RESULT: ' + res.getStatusCode() + ' ' + res.getBody().left(500));