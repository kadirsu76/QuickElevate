using Azure.Core;
using Azure.Identity;
using System.Text.Json.Serialization;

namespace QuickElevate.Api;

public sealed class GraphMembershipService(HttpClient httpClient, DefaultAzureCredential credential, BackendConfiguration configuration)
{
    public async Task<bool> IsMemberAsync(string objectId, CancellationToken cancellationToken)
    {
        var path = string.Equals(configuration.MembershipMode, "Direct", StringComparison.OrdinalIgnoreCase)
            ? "members"
            : "transitiveMembers/microsoft.graph.user";
        var nextUrl = $"https://graph.microsoft.com/v1.0/groups/{configuration.GroupObjectId}/{path}?$select=id";

        while (!string.IsNullOrWhiteSpace(nextUrl))
        {
            var token = await credential.GetTokenAsync(
                new TokenRequestContext(["https://graph.microsoft.com/.default"]), cancellationToken);

            using var request = new HttpRequestMessage(HttpMethod.Get, nextUrl);
            request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token.Token);
            using var response = await httpClient.SendAsync(request, cancellationToken);
            response.EnsureSuccessStatusCode();

            var page = await response.Content.ReadFromJsonAsync<GraphPage>(cancellationToken: cancellationToken)
                ?? throw new InvalidOperationException("Graph returned an empty response.");

            if (page.Value.Any(member => string.Equals(member.Id, objectId, StringComparison.OrdinalIgnoreCase)))
            {
                return true;
            }
            nextUrl = page.NextLink;
        }

        return false;
    }

    private sealed record GraphPage(
        GraphMember[] Value,
        [property: JsonPropertyName("@odata.nextLink")] string? NextLink);

    private sealed record GraphMember(string Id);
}
