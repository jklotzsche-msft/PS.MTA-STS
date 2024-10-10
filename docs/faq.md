# Frequently Asked Questions (FAQ)

## What is MTA-STS?

Mail Transfer Agent Strict Transport Security (MTA-STS) is a standard that allows domain owners to enable strict transport security for email traffic. MTA-STS is defined in [RFC8461](https://tools.ietf.org/html/rfc8461) and is a simple and effective way to prevent Man-in-the-middle attacks on email traffic. Microsoft has implemented MTA-STS for Exchange Online, and you can use this module to deploy and test MTA-STS for your domains hosted in Exchange Online.

## Why should I use MTA-STS?

MTA-STS is a new internet standard that improves email security and delivery for your organization. MTA-STS leverages the well-known security standard HTTPS, which is used to secure connections to websites, to enable organizations to assert policies and requirements for their email services. MTA-STS also enables organizations to request that remote email servers deliver email messages over a secure connection and to report back on any failures encountered. This helps to ensure that email messages are delivered in a secure and reliable manner.

To learn more check out our visualized [MTA-STS Infographic](./mta-sts-infographic.md).

## How do I deploy MTA-STS for my domain?

You can deploy and configure MTA-STS for your Exchange Online tenant manually in the Azure Portal or automatically using our `New-PSMTASTSFunctionAppDeployment` function. The `New-PSMTASTSFunctionAppDeployment` function deploys an Azure Function app that automatically configures MTA-STS for your domain in Exchange Online. To learn more about how to deploy MTA-STS for your domain, check out our [deployment guide](./docs/deploy-mta-sts.md).

## Can I change the App Service Plan for the Azure Function?

Yes, you can specify an existing App Service Plan when deploying the Azure Function app automatically using the `New-PSMTASTSFunctionAppDeployment` function. You can also change the App Service Plan for the Azure Function app manually in the Azure portal after deployment. To do this, check out the [official documentation from Microsoft](https://learn.microsoft.com/en-us/azure/app-service/app-service-plan-manage#move-an-app-to-another-app-service-plan).

## How do I test MTA-STS for my domain?

You can use the `Test-PSMTASTSConfiguration` function to test MTA-STS for your domain. Test-PSMTASTSConfiguration checks if MTA-STS is configured correctly for all domains in a CSV file. It checks if the TXT record is configured correctly, CNAME record is configured correctly, policy file is available and MX record is configured correctly.

## I created the Function App with runtime "PowerShell 7.2", but it's about to be deprecated. How can I update the runtime?

Luckily, you do not have to rebuild your Function App from scratch. You can update the existing Function App to the latest runtime through the Azure Portal. Please see the [official documentation from Microsoft](https://github.com/Azure/azure-functions-powershell-worker/wiki/Upgrading-your-Azure-Function-Apps-to-run-on-PowerShell-7.4#how-to-upgrade) for more information.

## "Classic Application Insights was retired on February 29, 2024" message in Application Insights resource. What does this mean?

This message is a notification from Microsoft that the Classic Application Insights resource has been retired. You can safely ignore this message as it does not affect the functionality of the MTA-STS module or your Azure Function App by default. If you want to learn more about the retirement of Classic Application Insights, check out the [official documentation from Microsoft](https://azure.microsoft.com/en-us/updates/we-re-retiring-classic-application-insights-on-29-february-2024/).

Additionally, you can disable Application Insights for new deployments of the Azure Function App by adding the `-DisableApplicationInsights` switch parameter in the `New-PSMTASTSFunctionAppDeployment` function. By default, Application Insights is enabled for new deployments of the Azure Function App.

## I enabled DNSSEC and SMTP DANE for some domains. Do I have to do something with my MTA-STS configuration?

Yes, if you enabled DNSSEC and SMTP DANE for some domains, you have to adjust the MTA-STS policy file to include the MX endpoint of your domain. You can update the MTA-STS policy file manually in the Azure Portal or automatically using the `Update-PSMTASTSFunctionAppFile` function. By using the `Update-PSMTASTSFunctionAppFile` function, the `*.mail.protection.outlook.com` MX endpoint will be added automatically to the MTA-STS policy file. The following example shows how to update the MTA-STS policy file to include the MX endpoint of your domains:

``` PowerShell
Update-PSMTASTSFunctionAppFile -ResourceGroupName 'rg-PSMTASTS' -FunctionAppName 'func-PSMTASTS' -PolicyMode 'Enforce' -ExoHostName '*.a-v1.mx.microsoft', '*.b-v1.mx.microsoft', '*.c-v1.mx.microsoft'
```

Afterwards, your MTA-STS policy file would look like this:

``` Text
version: STSv1
mode: enforce
mx: mail.protection.outlook.com
mx: *.a-v1.mx.microsoft
mx: *.b-v1.mx.microsoft
mx: *.c-v1.mx.microsoft
max_age: 604800
```

> **IMPORTANT NOTE** Please remember, that you should not use `*.mx.microsoft` for your DNSSEC and SMTP DANE enabled domains. Instead, you should use the full MX endpoint for your domain or the wildcard for your MX endpoints in a certain, auto-generated sub-zone. So if you have `contoso-com.a-v1.mx.microsoft` as MX record for your `contoso.com` domain, you can add it to the MTA-STS policy file as `*.a-v1.mx.microsoft` or `contoso-com.a-v1.mx.microsoft` but NOT as `*.mx.microsoft`.
