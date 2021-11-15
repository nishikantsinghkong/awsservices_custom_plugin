# awsservices_custom_plugin
Custom plugin code to connect with AWS Services. Starting with AWS Secrets Manager, this will be an evolving repo where more can be added to connect with  other additional AWS services in future. 
For now- we have integration with AWS dynamodb and AWS Secrets Manager services.
1. **To use AWS Secrets Manager**- 
    a. Enable the custom plugin on a route/services and select the Config.AWS Service dropdown list, provide other attributes (such as optioanl AWS credentials if you are running this Kong instance from outside AWS env) 
    b. provide a secretkey as a header in the request. the response to the route will either return the value of secret, or an appropriate message if secret was not found

2. **To user AWS Dynamodb**- 
  a. Enable the custom plugin agasint a route or service object as needed. During the configuration of plugin, select the type of Config.AWS Service as "dynamodb", provide AWS credentials and setup the confif ready to be tested against the route etc. 
provide two header name-value pairs for GetItem to work. one header is "tablename" and other header would be "key". this key header must contain the primary attribute of the item from dynamodb.  
