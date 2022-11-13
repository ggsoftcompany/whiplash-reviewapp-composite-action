 param (
    [Parameter(Mandatory=$true)]
    [string]$herokuApiKey,

    [Parameter(Mandatory=$true)]
    [string]$appName
)

Write-Output "====  Beginning - Delete Review App script  ==="

$herokuApiBaseURL = "https://api.heroku.com"
# heroku request header definition
$herokuRequestHeader = @{
    "Authorization" = "Bearer $herokuApiKey"
    "Content-Type" = "application/json"
    "Accept" = "application/vnd.heroku+json;version=3"
}

$reviewAppInstance = $null
try{
    $uri = "$herokuApiBaseURL/apps/$appName/review-app"
    Write-Output "Getting the review app by name..."
    Write-Output " Name: $appName"
    Write-Output "GET Request URL: $uri"
    $reviewAppInstance = Invoke-RestMethod -Method Get -Uri $uri -Headers $herokuRequestHeader -Verbose -Debug
    $reviewAppInstance
}
catch{
    write-warning "Review APP Not Found. Please verify that the provided name is correct."
}

if($reviewAppInstance != $null){
    try{
        Write-Output "Removing the review app..."
        Write-Output "DELETE Request URL: $uri"
        $uri = "$herokuApiBaseURL/review-apps/$($reviewAppInstance.id)"
        Invoke-RestMethod -Method Delete -Uri $uri -Headers $herokuRequestHeader -Verbose -Debug
        Write-Output "Review app removed."
    }
    catch{
        write-warning "The Review App couldn't be removed. If it is important to remove it, please contact DevOps team."
        $exceptionMessage = $_.Exception.Message
        Write-Output $exceptionMessage
        Write-Output $_.ErrorDetails
    }
}

Write-Output "====  END - Delete Review App script ==="
