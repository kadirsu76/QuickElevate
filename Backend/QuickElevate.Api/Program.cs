using Azure.Identity;
using Azure.Security.KeyVault.Keys.Cryptography;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using QuickElevate.Api;

var host = new HostBuilder()
    .ConfigureFunctionsWebApplication()
    .ConfigureServices(services =>
    {
        services.AddSingleton(new DefaultAzureCredential());
        services.AddHttpClient<GraphMembershipService>();
        services.AddSingleton<BackendConfiguration>();
        services.AddSingleton<GrantSigner>();
    })
    .Build();

host.Run();
