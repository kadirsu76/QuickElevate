# Threat Model

## Security invariants

- A local app button, Touch ID result, VPN interface, client-provided duration, or Boolean API response never independently grants admin rights.
- The root helper accepts only a valid backend-signed grant bound to the local request nonce, user, device, action, and expiration.
- The backend accepts only single-tenant Entra access tokens intended for its API.
- New grants fail closed when VPN, private DNS, Entra, Graph, Key Vault, or replay storage is unavailable.
- Existing grants expire locally even after VPN loss.

## Residual risk

A user made local administrator can create durable system changes during the allowed window. Removing their original `admin` group membership does not undo those changes. Keep duration short, require PIM, protect the helper, monitor admin-group changes, and use EDR.

## Non-goals

QuickElevate is not per-process elevation. It grants local administrator membership temporarily.
