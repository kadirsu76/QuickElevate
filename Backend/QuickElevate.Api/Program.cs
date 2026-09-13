using Azure.Identity;
using Azure.Security.KeyVault.Keys;
using Azure.Security.KeyVault.Keys.Cryptography;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using QuickElevate.Api;

var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureServices(services =>
    {
        services.AddSingleton(new DefaultAzureCredential());
        services.AddSingleton<KeyClient>(provider =>
        {
            var config = provider.GetRequiredService<BackendConfiguration>();
            var keyUri = new Uri(config.KeyVaultKeyId);
            return new KeyClient(new Uri($"{keyUri.Scheme}://{keyUri.Host}"), provider.GetRequiredService<DefaultAzureCredential>());
        });
        services.AddHttpClient<GraphMembershipService>();
        services.AddSingleton<BackendConfiguration>();
        services.AddSingleton<GrantSigner>();
    })
    .Build();

host.Run();
