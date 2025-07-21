* Rename to regionhop
* The new name for this project is regionhop. Replace any mentions of ownvpn in documentation and code or infra resource names with regionhop. The hop.sh file should not change to regionhop.sh for brevity.
* Health check and status should check the actual VPN service instead of CloudFormation stack status and IP availability. One command is enough for this, remove the other.
