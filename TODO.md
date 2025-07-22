* Add remove-client command to hop.sh and make sure client IP assignments don't conflict because the next IP is calculated based on the number of clients currently.
    * Let's improve client management. We need to add a command remove-client to hop.sh that removes a client from the wireguard configuration as well as key material and config files from the server and the s3 state bucket.

    Note that client IP addresses are now based on counting the number of clients and incrementing by one (in the add-client.sh written to the server by the userdata script). This needs to be improved so that IPs don't conflict when a client is removed and a new one is added. Perhaps we need to list all the IPs in use and assign the next available one?
* Health check and status should check the actual VPN service instead of CloudFormation stack status and IP availability. One command is enough for this, remove the other.
