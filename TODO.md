* Health check and status should check the actual VPN service instead of CloudFormation stack status and IP availability. One command is enough for this, remove the other.
* Create the server scripts as actual files in the repo instead of crazy printf userdata script stuff. Deployment should copy them to s3 bucket and ec2 instance will sync from there.
