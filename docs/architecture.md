# Architecture

QuickElevate grants temporary local administrator membership only after a private Azure authorization API approves the request.

```text
QuickElevate.app -> VPN or GSA -> Private Endpoint -> Azure Function
                                                   -> Graph membership check
                                                   -> Key Vault signing key
QuickElevate.app -> local IPC -> root helper -> verify signed grant -> admin group
```

The Function is reachable only through its Private Endpoint. Public network access is disabled. VPN or GSA is responsible for route and DNS delivery; the app does not depend on a specific VPN vendor.

## Authorization

1. The app obtains an Entra access token for the QuickElevate API through MSAL silent acquisition from the existing Platform SSO/Company Portal session. Interactive login is prohibited.
2. The app sends the token and a helper-generated nonce to `POST /api/v1/elevation-authorizations`.
3. Easy Auth validates authentication. The API authorizes by the token's immutable `tid` and `oid` claims.
4. The Function uses its Managed Identity and Microsoft Graph to test configured security group membership.
5. On allow, the API returns an asymmetric, short-lived, single-use signed grant.
6. The helper verifies the grant before it adds the active console user to local `admin`.
7. The helper controls the expiration and removes only membership it added.

## Network modes

`PrivateEndpoint` is the production default. The API hostname resolves to a private IP only through VPN/GSA DNS.

`VpnEgressAllowlist` is an optional future compatibility mode. It is cheaper but leaves a public endpoint protected by IP restrictions and is not equivalent to private connectivity.

## Identity mapping

The backend authorizes the Entra user by `(tid, oid)`, never by email/UPN. The local helper authorizes the active console UID. Production enrollment must bind those identities using a managed Platform SSO/WPJ mapping or another approved enrollment record. A UPN-to-short-name rule is display-only unless explicitly accepted as a lower-assurance fallback.
