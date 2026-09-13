# VPN and Global Secure Access

QuickElevate is VPN-vendor independent. The macOS application does not establish a tunnel or identify a VPN product. It calls the configured API hostname and fails closed if the private endpoint cannot be reached.

## Required network behavior

Every supported network product must provide both:

1. A route from the Mac to the Azure Private Endpoint subnet.
2. DNS resolution of `privatelink.azurewebsites.net` to the Function private endpoint address.

The app continues using the normal hostname:

```text
https://<function-app-name>.azurewebsites.net
```

When private DNS is configured, that hostname resolves through `<function-app-name>.privatelink.azurewebsites.net` to a private IP address. When the VPN/GSA path is unavailable, the API must not be reachable. Function App public network access remains disabled.

## Global Secure Access

Publish the Function hostname on TCP 443 as a Private Access application segment. The GSA connector must have reachability to the Azure VNet/private endpoint and DNS path. Assign the traffic forwarding profile to intended users/devices.

## SSL VPN products

Cisco AnyConnect, Palo Alto GlobalProtect, FortiClient, Zscaler Private Access, Azure VPN Client, and similar products work when their profile sends the private endpoint subnet route and the private DNS zone to corporate DNS. Full tunnel is not required; a split-tunnel route for the private endpoint subnet is sufficient.

## DNS options

- Existing corporate DNS server with a conditional forwarder to Azure private DNS.
- Existing DNS forwarder reachable through VPN/GSA.
- Azure DNS Private Resolver, if no existing forwarding infrastructure is available. This adds a significant fixed cost and should not be the first choice for a small pilot.

Do not use a static hosts-file mapping. Private endpoint IPs can change.

## Validation

From a managed Mac while connected to the intended network path:

```bash
dig <function-app-name>.azurewebsites.net
curl -I https://<function-app-name>.azurewebsites.net
```

DNS must resolve to the private endpoint path. The unauthenticated HTTP response should be `401`, not a connection failure. Off VPN/GSA, the request must fail to reach the service.
