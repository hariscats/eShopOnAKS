#!/usr/bin/pwsh

[CmdletBinding(DefaultParameterSetName = 'Default')]
param(
    [Parameter(ParameterSetName = 'Default', Mandatory=$true)]
    [string] $AppName,

    [Parameter(ParameterSetName = 'Default', Mandatory=$true)]
    [string] $DomainName
)

. ./modules/eshop_functions.ps1
. ./modules/eshop_naming.ps1 -AppName $AppName -DomainName $DomainName

$PLACEHOLDER_VALUE = "eshop-placeholder"
$CERT_NAME = ${AppName}-${DomainName}.Replace(".", "-")

if( Test-Certificate -CertName $CERT_NAME -Namespace "aks-istio-ingress" ) {
  Write-Log -Message "Certificate already exists for ${CERT_NAME}"
    return
}

Write-Log -Message "Installing ${CERT_CHART_NAME} to ${APP_K8S_NAME} into AKS-ISTIO-INGRESS namespace"
helm upgrade --install eshop-certificates `
  --set APP_NAME=${AppName} `
  --set WEBAPP_DOMAIN=${.DomainName} `
  --set CERT.EMAIL_ADDRESS=${AppName}@${DomainName} `
  --set CERT.SHOP_URL_SERVICE_NAME=${PLACEHOLDER_VALUE} `
  --set CERT.SHOP_URL_CHALLENGE_PATH=${PLACEHOLDER_VALUE} `
  --set CERT.IDENTITY_URL_SERVICE_NAME=${PLACEHOLDER_VALUE} `
  --set CERT.IDENTITY_URL_CHALLENGE_PATH=${PLACEHOLDER_VALUE} `
./charts/certs 

Start-Sleep -Seconds 30

$urls = @{}
foreach( $ingress in $ingresses ) {
  $HOST_NAME = $(kubectl --namespace aks-istio-ingress get ingress ${ingress} -o jsonpath='{.spec.rules[*].host}')
  
  Write-Log -Message "Getting Challenge settings for ${HOST_NAME}"
  $urls.Add($HOST_NAME, (New-Object -Type psobject -Property @{
    CHALLENGE_PATH = $(kubectl --namespace aks-istio-ingress get ingress ${ingress} -o jsonpath='{.spec.rules[*].http.paths[0].path}')
    CHALLENGE_SERVICE_NAME = $(kubectl --namespace aks-istio-ingress get ingress ${ingress} -o jsonpath='{.spec.rules[*].http.paths[0].backend.service.name}')
  }))
}

$shop_key = ($urls.Keys | Where-Object {$_ -imatch "shop"})
$identity_key = ($urls.Keys | Where-Object {$_ -imatch "identity"})

Write-Log -Message "Modifiying ${CERT_CHART_NAME} to complete certificate request"
helm upgrade --install eshop-certificates `
  --set APP_NAME=${AppName} `
  --set WEBAPP_DOMAIN=${.DomainName} `
  --set CERT.EMAIL_ADDRESS=${AppName}@${DomainName} `
  --set CERT.SHOP_URL_SERVICE_NAME=$urls[$shop_key].CHALLENGE_SERVICE_NAME `
  --set CERT.SHOP_URL_CHALLENGE_PATH=$urls[$shop_key].CHALLENGE_PATH `
  --set CERT.IDENTITY_URL_SERVICE_NAME=$urls[$identity_key].CHALLENGE_SERVICE_NAME `
  --set CERT.IDENTITY_URL_CHALLENGE_PATH=$urls[$identity_key].CHALLENGE_PATH `
./charts/certs 