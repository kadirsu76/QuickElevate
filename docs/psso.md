# Platform SSO Token Policy

QuickElevate does not show a Microsoft Entra sign-in screen.

The macOS client uses MSAL only to request a token silently from the existing Microsoft Enterprise SSO plug-in/Company Portal Platform SSO session. It requests a new token for every elevation attempt with `forceRefresh` enabled so that current access policy is evaluated.

## Required behavior

- The client calls `acquireTokenSilent` only.
- The client never calls MSAL interactive token acquisition.
- No browser, web view, password prompt, or Entra account picker is opened by QuickElevate.
- If the current user has no usable Platform SSO account, elevation fails closed.
- The app displays an IT guidance message asking the user to complete Company Portal/Platform SSO registration.
- Touch ID or local macOS password is separate from Entra authentication and remains the local user-presence check.

## Token usage

The token is issued by Microsoft Entra for the QuickElevate private API scope:

```text
api://<QuickElevate-API-Application-ID>/Elevation.Request
```

The client sends the token only to the private API through the approved VPN/GSA route. The API's Easy Auth configuration validates tenant, audience, token lifetime, and the allowed native client application before the Function evaluates group membership.

PSSO does not by itself perform a group membership lookup. It provides the silent user token. The backend uses the validated token's `tid` and `oid` claims to evaluate the configured Entra security group.
