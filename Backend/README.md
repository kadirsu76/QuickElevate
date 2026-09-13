# QuickElevate Authorization API

This .NET 8 isolated Azure Function authorizes new elevation requests.

## Contract

`POST /api/v1/elevation-authorizations` requires an Entra access token for the API. App Service Authentication/Easy Auth must validate the token before the Function runs.

The endpoint:

1. Derives the caller from Entra `tid` and `oid` claims injected by Easy Auth.
2. Uses the Function Managed Identity to query the configured `GROUP_OBJECT_ID`.
3. Selects `members` for `Direct` mode or `transitiveMembers` for `Transitive` mode.
4. Signs a grant with an Azure Key Vault asymmetric key.

The API never accepts a user identity, security group ID, or authoritative duration from the macOS client.

## Required app settings

Copy `QuickElevate.Api/local.settings.example.json` outside source control for local development. Do not commit local settings.

## Required tenant permissions

The Function Managed Identity needs Microsoft Graph application permission `GroupMember.Read.All` and tenant admin consent. Do not grant Graph write permissions.

Run `Infrastructure/azure/setup-quickelevate.ps1` after infrastructure deployment. It creates the single-tenant API and native macOS app registrations, configures the `Elevation.Request` delegated scope and tenant-wide consent, enables Easy Auth, writes the non-secret client identifiers to Function settings, and assigns the Managed Identity Graph read permission.

## Current alpha limitation

The backend signs grant claims, but the macOS helper does not yet verify or consume the grant. The backend and helper must be released together once signed-grant verification and replay protection are implemented.
