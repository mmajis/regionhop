* Add script for stopping and starting instances to avoid charges when not in use. This will help to maintain the private key when instance is not destroyed.
  * DesiredCount to 0 to stop instances.
  * Could also add writing of keys to SSM secrets for resilience.
  * Need also client public keys in wg0.conf on server, need to create a backup solution to S3 maybe or maybe better to use SSM secrets.
* Change macos-client to default-client in client config generation.
  * Or remove default client and require use of `add-client` command.
* Clean up regions.js
* Rename to regionhop
