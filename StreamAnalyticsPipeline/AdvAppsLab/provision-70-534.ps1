Function Install-AdvancedApplicationsLab2 {

param(
	[Parameter(Mandatory=$true)]
	[String] $resourceGroupName,
	
	[Parameter(Mandatory=$true)]
	[String] $location
)

	try {
		$ctx = Get-AzureRMContext
	}
	catch {
		Write-Information "`nBefore running this script you must login to your Azure account (Login-AzureRMAccount) and select the subscription (Select-AzureRMSubscription) to which the services should be deployed`n" -InformationAction Continue
		exit
	}
	
	# ensure resource group exists
	$rg = Get-AzureRMResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
	
	# try to create it, if not
	if ($rg -eq $null) {
		$rg = New-AzureRMResourceGroup -Name $resourceGroupName -Location $location -ErrorAction Continue
	}
	
	# fail if no resource group at this point
	if ($rg -eq $null) {
		Write-Error '`nCannot deploy without a resource group as the destination'
		exit
	}
		
	# deploy the services
	Write-Information "`nDeploying Azure ARM template to resource group $($resourceGroupName) in subscription '$($ctx.Subscription.SubscriptionName)'..." -InformationAction Continue

	$result = New-AzureRmResourceGroupDeployment -ResourceGroupName $resourceGroupName `
			-TemplateFile "$($PSScriptRoot)\arm-advapps.json" `
			-ErrorAction Stop
			
	# get the name of the Azure Function app that was deployed
	$deployedFunctionName = $result.Outputs.functionName.Value
	
	# get the publishing credentials for the new function app
	Write-Information 'Retrieving publishing credentials...' -InformationAction Continue

	$creds = Invoke-AzureRmResourceAction -ResourceGroupName $resourceGroupName `
				-ResourceType Microsoft.Web/sites/config `
				-ResourceName "$($deployedFunctionName)/publishingcredentials" `
				-Action list -ApiVersion 2015-08-01 -Force
				
	$userName = $creds.Properties.publishingUserName
	$password = $creds.Properties.publishingPassword
	$scmUri = "https://$($creds.Properties.scmUri.split('@')[1])/api/zip/site/wwwroot"
	
	# deploy function app ZIP via Kudu REST ApiVersion
	# (with acknowledgements to Mark Heath: http://markheath.net/post/deploy-azure-functions-kudu-powershell)
	$authToken = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $userName, $password)))
	
	Write-Information 'Deploying function application...' -InformationAction Continue
	try {
		Invoke-RestMethod -Method PUT -Uri $scmUri `
	                  -Headers @{Authorization=("Basic {0}" -f $authToken)} `
					  -InFile "$($PSScriptRoot)\RecordAlert.zip" `
					  -ContentType "multipart/form-data"
					  
		Write-Information 'Provisioning complete. Open the Azure portal to complete the lab.'
	} catch {
		Write-Error $_.Exception.Message
	}
}

Install-AdvancedApplicationsLab2 -Location eastus