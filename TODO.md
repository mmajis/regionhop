Create the server scripts add-client.sh, remove-client.sh and vpn-status.sh as actual files in the repo instead of crazy printf userdata script stuff. Deployment should copy them to s3 bucket and ec2 instance will sync from there when it starts. The scripts are currently created from the userdata script with printf statements which is error prone to maintain now that the scripts are getting more functionality.

The files should be created in a new server-scripts directory and the deployment should copy them to the s3 bucket if they have changed since last deployment. The ec2 instance should sync them from the s3 bucket at startup.

The dynamic variables should be writte to an env.sh file which is sourced by the add-client and remove-client scripts. The env.sh file should contain the dynamically set variables such as server endpoint and subnet information.

The goal is to be able to copy the add-client and remove-client scripts (and the vpn-status script) to the EC2 instance as is from the S3 bucket without having to modify them for each deployment. Any dynamic variables should be placed in env.sh and sourced by the scripts. This way the files will be testable locally with mock values in a local env.sh file.
