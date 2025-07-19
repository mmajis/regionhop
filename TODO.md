* Add script for stopping and starting instances to avoid charges when not in use. This will help to maintain the private key when instance is not destroyed.
  * Could also add writing of keys to SSM secrets for resilience.
* Change macos-client to default-client in client config generation.
  * Or remove default client and require use of `add-client` command.
* Clean up regions.js
