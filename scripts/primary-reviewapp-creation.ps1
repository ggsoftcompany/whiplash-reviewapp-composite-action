 param (
    [Parameter(Mandatory=$false)]
    [string]$workingDirectoryPath = "lola",

    [Parameter(Mandatory=$true)]
    [string]$herokuApiKey,

    [Parameter(Mandatory=$true)]
    [string]$targetHerokuPipelineName
)


# variables
$herokuApiBaseURL = "https://api.heroku.com"

# heroku request header definition
$herokuRequestHeader = @{
    "Authorization" = "Bearer $herokuApiKey"
    "Content-Type" = "application/json"
    "Accept" = "application/vnd.heroku+json;version=3"
}

# verify if heroku pipeline exists
$herokuPipelineInstance = $null
$uri = "$herokuApiBaseURL/pipelines/$targetHerokuPipelineName"
try{
    Write-Output "Getting primary HEROKU pipeline details..."
    Write-Output "GET Request URL: $uri"
    $herokuPipelineInstance = Invoke-RestMethod -Method Get -Uri $uri -Headers $herokuRequestHeader -Verbose -Debug
    Write-Output $herokuPipelineInstance
}
catch{
    $exceptionMessage = $_.Exception.Message
    Write-Output $exceptionMessage
    Write-Output $_.ErrorDetails
    if($exceptionMessage -imatch "Not Found"){
        throw("Primary HEROKU Pipeline Not Found. Please verify that the provided pipeline name is correct.")
    }
    else{
        throw("Unexpected Error. $exceptionMessage.")
    }
}
Write-Output "*************************************************"




write-output "== DONE =="
