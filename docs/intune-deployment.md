# Intune Deployment

Deploy in this order:

1. The corporate VPN/GSA client, route, and private-DNS policy.
2. QuickElevate Service Management/background-item policy.
3. `deploy/QuickElevate-Configuration.mobileconfig.example`, completed with Azure deployment outputs.
4. `deploy/QuickElevate-Dock.mobileconfig` and `deploy/QuickElevate-Notifications.mobileconfig`.
5. The signed and notarized QuickElevate PKG as a required macOS PKG app.

Use `QuickElevate-Configuration.mobileconfig.example` only as a template. Replace every `<...>` value, generate new profile UUIDs, then upload it as a custom macOS profile.

Do not put Function keys, client secrets, Graph tokens, Key Vault credentials, or signing material in Intune scripts or profiles. The settings profile contains identifiers and URLs only.

The Intune post-install script is not the long-term settings channel. Use managed preferences so policy changes do not require a package reinstall.
