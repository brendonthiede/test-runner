using Microsoft.AspNetCore.Http;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.WindowsAzure.Storage;
using Microsoft.WindowsAzure.Storage.Blob;
using System;
using System.Threading.Tasks;

namespace TestRunner.Functions
{
    public static class GetUploadUrl
    {
        [FunctionName("GetUploadUrl")]
        public static async Task<object> Run(
            [HttpTrigger(AuthorizationLevel.Anonymous, "get", "post", Route = null)] HttpRequest req)
        {
            var isMissingParameter = false;
            var errorMessage = "";
            if (!req.GetQueryParameterDictionary().TryGetValue("filename", out string filenameParameter))
            {
                isMissingParameter = true;
                errorMessage += "\nfilename parameter is required";
            }
            if (!req.GetQueryParameterDictionary().TryGetValue("environment", out string environmentParameter))
            {
                isMissingParameter = true;
                errorMessage += "\nenvironment parameter is required";
            }

            if (isMissingParameter)
            {
                return new
                {
                    error = errorMessage
                };
            }

            var filename = filenameParameter;
            var environment = environmentParameter;

            CloudStorageAccount storageAccount = CloudStorageAccount.Parse(
                Environment.GetEnvironmentVariable("WEBSITE_CONTENTAZUREFILECONNECTIONSTRING", EnvironmentVariableTarget.Process));
            var client = storageAccount.CreateCloudBlobClient();
            var container = client.GetContainerReference(environment);
            await container.CreateIfNotExistsAsync();

            CloudBlockBlob blob = container.GetBlockBlobReference($"{filename}");

            SharedAccessBlobPolicy adHocSAS = new SharedAccessBlobPolicy()
            {
                SharedAccessExpiryTime = DateTime.UtcNow.AddMinutes(3),
                Permissions = SharedAccessBlobPermissions.Read | SharedAccessBlobPermissions.Write | SharedAccessBlobPermissions.Create
            };

            var sasBlobToken = blob.GetSharedAccessSignature(adHocSAS);
            return new
            {
                url = blob.Uri + sasBlobToken
            };
        }
    }
}
