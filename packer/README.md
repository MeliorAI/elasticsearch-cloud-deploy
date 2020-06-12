# Elasticsearch and Kibana machine images

This Packer configuration will generate Ubuntu images with Elasticsearch, Kibana and other important tools for deploying and managing Elasticsearch clusters on the cloud.

The output of running Packer here would be two machine images, as below:

* elasticsearch node image, containing latest Elasticsearch installed (latest version 7.x) and configured with best-practices.
* kibana node image, based on the elasticsearch node image, and with Kibana (7.x, latest), nginx with basic proxy and authentication setip, and Kopf.

## On Amazon Web Services (AWS)

Using the AWS builder will create the two images and store them as AMIs.

As a convention the Packer builders will use a dedicated IAM roles, which you will need to have present.

```bash
aws iam create-role --role-name packer --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": {
    "Effect": "Allow",
    "Principal": {"Service": "ec2.amazonaws.com"},
    "Action": "sts:AssumeRole",
    "Sid": ""
  }
}'
```

Response will look something like this:

```json
{
    "Role": {
        "AssumeRolePolicyDocument": {
            "Version": "2012-10-17",
            "Statement": {
                "Action": "sts:AssumeRole",
                "Effect": "Allow",
                "Principal": {
                    "Service": "ec2.amazonaws.com"
                }
            }
        },
        "RoleId": "AROAJ7Q2L7NZJHZBB6JKY",
        "CreateDate": "2016-12-16T13:22:47.254Z",
        "RoleName": "packer",
        "Path": "/",
        "Arn": "arn:aws:iam::611111111117:role/packer"
    }
}
```

Follow up by executing the following

```bash
aws iam create-instance-profile --instance-profile-name packer
aws iam add-role-to-instance-profile  --instance-profile-name packer --role-name packer
```

By default, AWS builder will pick a subnet from the default VPC for running the builder instance. It is required for that subnet to have Public IPs auto-assignment enabled. Otherwise, packer won't be able to make a SSH connection to the instance and will hang on `Waiting for SSH to become available...`
If you don't want to enable public IPs auto-assignment on your default VPC subnets, you can explicitly set the subnet by setting `vpc_id` and `subnet_id` keys in *.packer.json files `amazon-ebs` builder definitions.

## [On Microsoft Azure](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/build-image-with-packer)

Before running Packer for the first time you will need to do a one-time initial setup.

### Power-Shell

Use Power-Shell, and [login to AzureRm](https://docs.microsoft.com/en-us/powershell/azure/authenticate-azureps). 

Once logged in, take note of the subscription and tenant IDs which will be printed out.
Alternatively, you can retrieve them by running `Get-AzureRmSubscription` once logged-in.

```Powershell
$rgName = "packer-elasticsearch-images"
$location = "East US"
New-AzureRmResourceGroup -Name $rgName -Location $location

$sp = New-AzureRmADServicePrincipal -DisplayName "AzurePackerIKF"
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sp.Secret)

# If this displays just one character
$PlainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
$PlainPassword

# Then try:
$PlainPassword = ConvertFrom-SecureString -SecureString $newCredential.Secret -AsPlainText
$PlainPassword

# Role 'Contributor' seems not to be sufficient?
New-AzureRmRoleAssignment -RoleDefinitionName Contributor -ServicePrincipalName $sp.ApplicationId

$sp.ApplicationId
```

> **NOTE**: The above seems to not return a proper password

If that's the case might be needed to  of the _Service Principal_.

Note the `resource group name`,`location`, `password` and `sp.ApplicationId` as used in the script and emitted as output and update `variables.json`.

> **To learn more:** [Packer on Azure](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/build-image-with-packer)



#### Useful Power-Shell commands:

* Retrieve Azure Active Directory Service Principal by name
```Powershell
Get-AzADServicePrincipal -DisplayName AzurePackerIKF
```

* [Reset the credentials](https://docs.microsoft.com/en-us/powershell/azure/create-azure-service-principal-azureps?view=azps-4.2.0) (creates a new **random** password)
```PowerShell
$newCredential = New-AzADSpCredential -ServicePrincipalName http://AzurePackerIKF
$plainPassword = ConvertFrom-SecureString -SecureString $newCredential.Secret -AsPlainText
$plainPassword
```
> **NOTE**: The `ServicePrincipalName` is to be taken from the `Get-AzADServicePrincipal` command

### Azure CLI

Similarly, using the Azure CLI is going to look something like below:

```bash
export rgName=packer-elasticsearch-images
az group create -n ${rgName} -l eastus

az ad sp create-for-rbac --query "{ client_id: appId, client_secret: password, tenant_id: tenant }"
# outputs client_id, client_secret and tenant_id
az account show --query "{ subscription_id: id }"
# outputs subscription_id
```

## Building

Building the AMIs is done using the following commands:

```bash
packer build -only=amazon-ebs -var-file=variables.json elasticsearch7-node.packer.json
packer build -only=amazon-ebs -var-file=variables.json kibana7-node.packer.json
```

> Replace the `-only` parameter to `azure-arm` to build images for Azure instead of AWS.
