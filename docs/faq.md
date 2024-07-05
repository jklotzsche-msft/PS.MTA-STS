# Frequently Asked Questions (FAQ)

## What is MTA-STS?

Mail Transfer Agent Strict Transport Security (MTA-STS) is a standard that allows domain owners to enable strict transport security for email traffic. MTA-STS is defined in [RFC8461](https://tools.ietf.org/html/rfc8461) and is a simple and effective way to prevent Man-in-the-middle attacks on email traffic. Microsoft has implemented MTA-STS for Exchange Online, and you can use this module to deploy and test MTA-STS for your domains hosted in Exchange Online.

## Why should I use MTA-STS?

MTA-STS is a new internet standard that improves email security and delivery for your organization. MTA-STS leverages the well-known security standard HTTPS, which is used to secure connections to websites, to enable organizations to assert policies and requirements for their email services. MTA-STS also enables organizations to request that remote email servers deliver email messages over a secure connection and to report back on any failures encountered. This helps to ensure that email messages are delivered in a secure and reliable manner.

To learn more check out our visualized [MTA-STS Infographic](./docs/mta-sts-infographic.md).

## How do I deploy MTA-STS for my domain?

You can deploy and configure MTA-STS for your Exchange Online tenant manually in the Azure Portal or automatically using our `New-PSMTASTSFunctionAppDeployment` function. The `New-PSMTASTSFunctionAppDeployment` function deploys an Azure Function app that automatically configures MTA-STS for your domain in Exchange Online. To learn more about how to deploy MTA-STS for your domain, check out our [deployment guide](./docs/deploy-mta-sts.md).

## Can I change the App Service Plan for the Azure Function?

Yes, you can specify an existing App Service Plan when deploying the Azure Function app automatically using the `New-PSMTASTSFunctionAppDeployment` function. You can also change the App Service Plan for the Azure Function app manually in the Azure portal after deployment. To do this, check out the [official documentation from Microsoft](https://learn.microsoft.com/en-us/azure/app-service/app-service-plan-manage#move-an-app-to-another-app-service-plan).

## How do I test MTA-STS for my domain?

You can use the `Test-PSMTASTSConfiguration` function to test MTA-STS for your domain. Test-PSMTASTSConfiguration checks if MTA-STS is configured correctly for all domains in a CSV file. It checks if the TXT record is configured correctly, CNAME record is configured correctly, policy file is available and MX record is configured correctly.
