# Migrate MTA-STS deployment from Azure Static Web App or old Azure Function App to new Azure Function App

This guide will help you to migrate your MTA-STS deployment from an Azure Static Web App or an old Azure Function App to a new Azure Function App.
This can also be useful, if you want to migration from one tenant to another tenant.

## Step 1: Create a new Azure Function App

Follow the guidance at [Deploy MTA-STS using a Azure Function App](./deployFunctionApp.md) to create a new Azure Function App (Step 2)

## Step 2: Edit TTL of your DNS Records

Edit the TTL of your DNS Records to a lower value. This will help you to switch the DNS Records faster to the new Azure Function App. Wait for the TTL of the DNS records to expire.
> Note: The MTA-STS policy file has it's own TTL (default in our Function App: 604800 seconds = 7 days). So you can change the TTL of the DNS Records to a lower value, but the MTA-STS policy file will still be cached for 7 days. If you make this change to make a new policy file effective, you have to wait maximum 7 days until the old policy file is expired.

## Step 3: Update DNS records to point to the new Azure Function App

Add the custom domains to the new Azure Function App. Follow the guidance at [Deploy MTA-STS using a Azure Function App](./deployFunctionApp.md) to add the custom domains (Step 3)
> Note: When you update the DNS records, but the custom domain is not yet added to the new Azure Function App, the MTA-STS policy will not be served. In this case, the following behavior will occur according to the [RFC8461](https://datatracker.ietf.org/doc/html/rfc8461):

``` Text
   If a valid TXT record is found but no policy can be fetched via HTTPS
   (for any reason), and there is no valid (non-expired) previously
   cached policy, senders MUST continue with delivery as though the
   domain has not implemented MTA-STS.
```

## Step 4: Add custom domain to new Azure Function App

Add the custom domains to the new Azure Function App. Follow the guidance at [Deploy MTA-STS using a Azure Function App](./deployFunctionApp.md) to add the custom domains (Step 4)

## Step 5: Remove custom domains from old Azure Static Web App or Azure Function App

Now, the custom domain(s) are configured in multiple Azure resources, but only the new Azure Function App will serve the MTA-STS policy, because the DNS records are pointing to the new Azure Function App. So, you can remove the custom domains from the old Azure Static Web App or Azure Function App.

You can do so manually in the Azure Portal or by using the prepared function `Remove-PSMTASTSCustomDomain` from the PS.MTA-STS module.

``` Powershell
Remove-PSMTASTSCustomDomain -ResourceGroupName 'rg-myMTASTSDeployment' -FunctionAppName 'func-myMTASTSDeployment' -DomainName 'contoso.com'
```

## Step 6: Update the MTA-STS TXT record

If your MTA-STS policy file has changed due to this change (e.g. mode was 'testing' and is now 'enforce'), you can update the MTA-STS TXT record to indicate, that the MTA-STS policy file has changed. This will help the senders to fetch the new policy file faster.

To do so, update the ID in the MTA-STS TXT record. The ID can be the current date.

| Name | Type | Value |
| ---- | ---- | ----- |
| _mta-sts.\<your-custom-domain> | TXT | v=STSv1; id=\<your own unique id, e.g. the current date as 20230712120000>Z; |