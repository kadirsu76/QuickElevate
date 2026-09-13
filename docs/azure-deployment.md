# Azure Deployment

The deploy template asks for `pimGroupObjectId`. This immutable Entra group object ID stays on the backend and is never supplied by the macOS client.

The template creates private-network resources only. After deployment a tenant administrator must grant the Function Managed Identity Microsoft Graph application permission `GroupMember.ReadBasic.All` and grant admin consent. No Graph write permission is required.

For `membershipMode=Transitive`, the backend accepts direct or nested membership. For stricter PIM semantics select `Direct`.
