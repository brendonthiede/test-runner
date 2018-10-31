using Microsoft.AspNetCore.Http;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.WindowsAzure.Storage;
using System;
using System.Threading.Tasks;

namespace TestRunner.Functions
{
    public static class GetContainerAccessToken
    {
        [FunctionName("GetContainerAccessToken")]
        public static object Run(
            [HttpTrigger(AuthorizationLevel.Function, "get", "post", "option", Route = null)] HttpRequest req)
        {
            CloudStorageAccount storageAccount = CloudStorageAccount.Parse(
                Environment.GetEnvironmentVariable("WEBSITE_CONTENTAZUREFILECONNECTIONSTRING", EnvironmentVariableTarget.Process));
            SharedAccessAccountPolicy policy = new SharedAccessAccountPolicy()
            {
                Permissions = SharedAccessAccountPermissions.Read | SharedAccessAccountPermissions.List,
                Services = SharedAccessAccountServices.Blob,
                ResourceTypes = SharedAccessAccountResourceTypes.Service,
                SharedAccessExpiryTime = DateTime.UtcNow.AddHours(1),
                Protocols = SharedAccessProtocol.HttpsOnly
            };

            var accessToken = storageAccount.GetSharedAccessSignature(policy);
            var blobEndpoint = storageAccount.BlobEndpoint;

            return new
            {
                accessToken,
                blobEndpoint
            };
        }
    }
}
