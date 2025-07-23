* Health check and status should check the actual VPN service instead of CloudFormation stack status and IP availability. One command is enough for this, remove the other.
    * Consolidate the health and status commands in hop.sh to a single status command.

        If no region is given, the command will check statuses of all deployed regions. A deployed region means there exists at least one CloudFormation stack where the name starts with RegionHop. Update the "deployed" command to reflect this.

        If a region is given, the command will check status of that specific region.

        Statuses are: 
        * RUNNING: The VPN server responds on the configured VPN port.
        * STOPPED: The deployment is complete and the auto scaling group desiredCapacity is 0.
        * UNHEALTHY: The region is deployed, auto scaling desiredCapacity is 1 but the server does not respond on the configured VPN port.
* Create the server scripts as actual files in the repo instead of crazy printf userdata script stuff. Deployment should copy them to s3 bucket and ec2 instance will sync from there.
