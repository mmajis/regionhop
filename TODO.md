* Test without DNS after a lot of changes with DNS management enabled
* Make instance type and spot vs on-demand configurable to enable use of AWS free tier
* Create wg0.conf from scratch every time and add peers from backed up client-configs material. This will allow change of subnet or adding/removing ipv4/ipv6 without having to delete the whole WireGuard config or editing or other tricks.
