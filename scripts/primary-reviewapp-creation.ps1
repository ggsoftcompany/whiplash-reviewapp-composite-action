 param (
    [Parameter(Mandatory=$true)]
    [string]$workingDirectoryPath,

    [Parameter(Mandatory=$true)]
    [string]$herokuApiKey,

    [Parameter(Mandatory=$true)]
    [string]$githubAccessToken,

    [Parameter(Mandatory=$true)]
    [string]$githubRepositoryFullName,

    [Parameter(Mandatory=$true)]
    [string]$githubFullBranchName,

    [Parameter(Mandatory=$true)]
    [string]$sourceCodeVersion,

    [Parameter(Mandatory=$true)]
    [string]$herokuPipelineName,

    [Parameter(Mandatory=$true)]
    [string]$reviewAppPrefixURL,

    [Parameter(Mandatory=$false)]
    [string]$reviewAppEnvironmentValues = "",

    [Parameter(Mandatory=$true)]
    [string]$secondaryReviewAppPrefixURL,

    [Parameter(Mandatory=$true)]
    [string]$secondaryReviewAppNewBranchPrefix
)

Write-Output "====  Beginning - Script of the Primary HEROKU Review APP  ==="

# variables
$herokuApiBaseURL = "https://api.heroku.com"
$pullRequestNumber = $githubFullBranchName.Replace("refs/pull/", "").Replace("/merge", "").trim()
$branchName = $githubFullBranchName.Replace("refs/", "").trim()


# set a variable with the projected URL for the Primary review App.
# this variable will be used in post scripts
$reviewAppURL = "https://$reviewAppPrefixURL-pr-$pullRequestNumber.herokuapp.com"
echo "reviewapp_URL=$($reviewAppURL)"

# set a variable with the projected URL for the Secondary(secondary) review App.
$secondaryReviewAppTargetBranchName = [string]::Format("{0}{1}", $secondaryReviewAppNewBranchPrefix, $pullRequestNumber)
$secondaryReviewAppURL = "https://$secondaryReviewAppPrefixURL-br-$secondaryReviewAppTargetBranchName.herokuapp.com"
echo "secondaryReviewapp_URL=$($secondaryReviewAppURL)"

return
# heroku request header definition
$herokuRequestHeader = @{
    "Authorization" = "Bearer $herokuApiKey"
    "Content-Type" = "application/json"
    "Accept" = "application/vnd.heroku+json;version=3"
}

# verify if heroku pipeline exists
$herokuPipelineInstance = $null
$uri = "$herokuApiBaseURL/pipelines/$herokuPipelineName"
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

# verify if exists already a review app related with the pull request
$herokuPipelineInstanceID = $herokuPipelineInstance.id
$uri = "$herokuApiBaseURL/pipelines/$herokuPipelineInstanceID/review-apps"
Write-Output "Verify if exists already a review app related with the pull request..."
$appReviewList = Invoke-RestMethod -Method Get -Uri $uri -Headers $herokuRequestHeader -Verbose -Debug
Write-Output "GET Request URL: $uri"
$reviewAppInstance = $appReviewList.where{$_.branch.trim() -eq $branchName}
if($reviewAppInstance.count -gt 0){
    Write-Warning "The pipeline: $targetHerokuPipelineName already have a Review APP for the pull request: $pullRequestNumber."
    Write-Output $reviewAppInstance
    Write-Output "Finishing execution of the primary review app process...."
    Write-Output " DONE "
    # set a control variable to skip the execution of the subsequent tasks
    return
}
Write-Output "Review APP Not Found."
Write-Output "*************************************************"

# github request header definition
$githubRequestHeader = @{
    Accept = "application/vnd.github+json"
    Authorization = "token $githubAccessToken"
}

# download the source code related with the pull request from github.
Write-Output "Downloading the source code related with the pull request from github..."
$uri = "https://api.github.com/repos/$githubRepositoryFullName/tarball/$githubFullBranchName"
Write-Output "GET Request URL: $uri"
$sourceCodeFileName = $githubRepositoryFullName.Replace('/', '___') + "-pr-$pullRequestNumber.tgz"
$sourceCodeDownloadPath = "$workingDirectoryPath/$sourceCodeFileName"
try{
    Invoke-RestMethod -Uri $uri -Headers $githubRequestHeader -Method Get -OutFile $sourceCodeDownloadPath -Verbose -Debug | Out-Null
    Write-Output "Source Code Found."
    Write-Output "Downloading Path: $sourceCodeDownloadPath"

    # set output variables
    #echo "##vso[task.setvariable variable=ReviewAppSourceCodeDownloadPath;isOutput=true]$sourceCodeDownloadPath"
    #echo "##vso[task.setvariable variable=ReviewAppSourceCodeFileName;isOutput=true]$sourceCodeFileName"
}
catch{
    $exceptionMessage = $_.Exception.Message
    if($exceptionMessage -imatch "(404) Not Found"){
        throw("Source Code Not Found. Please verify that all values in the URL are correct.")
    }
    else{
        throw("Unexpected Error. $exceptionMessage.")
    }
}
Write-Output "*************************************************"

# uploading the source code into a heroku source(HEROKU source will provide an url of the code that we can use to create the review app later).
Write-Output "Creating a source instance in HEROKU..."
$uri = "$herokuApiBaseURL/sources"
Write-Output "POST Request URL: $uri"
$herokuSourceInstance = Invoke-RestMethod -Method Post -Uri $uri -Headers $herokuRequestHeader -Verbose -Debug
Write-Output "HEROKU source instance created."
$herokuSourceInstance

Write-Output "Uploading the source code into the HEROKU source instance..."
$uri = $herokuSourceInstance.source_blob.put_url
Write-Output "PUT Request URL: $uri"
try{
    Invoke-RestMethod -Method Put -Uri $uri -InFile $sourceCodeDownloadPath -Verbose -Debug
    Write-Output "Uploading completed."
}
catch{
    Write-Output "Unexpected Error uploading the source code into HEROKU."
    Write-Output "Error details: "
    Write-Output $_.Exception.Message
    Write-Output $_.ErrorDetails
    throw $_
}
Write-Output "*************************************************"

# lets begin creating the review app

# first lets set up the default values for the environment configuration the review app will use
# so far only ensure that the UI_URL configuration is present
Write-Output "Setting up the default environment variable values for the Primary Review App.."
$environmentValuesAsObject = [PSCustomObject]@{}
if(![string]::IsNullOrWhiteSpace($reviewAppEnvironmentValues)){
    $environmentValuesAsObject = $reviewAppEnvironmentValues | ConvertFrom-Json
}
$environmentValuesAsObject | Add-Member -MemberType NoteProperty -Name 'FRONTEND_URL' -Value $secondaryReviewAppURL  -Force
$environmentValuesAsObject | Add-Member -MemberType NoteProperty -Name 'APP_URL' -Value $reviewAppURL  -Force
Write-Output $environmentValuesAsObject

Write-Output "*************************************************"

Write-Output "Creating the Primary Review APP..."
# request body
$createReviewAppRequestBody = @{
  branch = $branchName
  pr_number = [int]::Parse($pullRequestNumber)
  pipeline = $herokuPipelineInstanceID
  source_blob = @{
    url = $herokuSourceInstance.source_blob.get_url
    version = $sourceCodeVersion
  }
  environment = $environmentValuesAsObject
}

$createReviewAppRequestBody = $createReviewAppRequestBody| ConvertTo-Json -Depth 10
$uri = "$herokuApiBaseURL/review-apps"
$reviewAppInstance = $null
try{
    Write-Output "POST Request URL: $uri"
    Write-Output "POST Request Body: "
    Write-Output $createReviewAppRequestBody
    $reviewAppInstance = Invoke-RestMethod -Method Post -Uri $uri -Headers $herokuRequestHeader -Body $createReviewAppRequestBody -Verbose -Debug
    Write-Output "Review APP creation details: "
    Write-Output $reviewAppInstance | ConvertTo-Json -Depth 10
}
catch{
    Write-Output "Unexpected Error while creating the Primary HEROKU Review APP."
    Write-Output "Error details: "
    Write-Output $_.Exception.Message
    Write-Output $_.ErrorDetails
    throw $_
}

Write-Output "*************************************************"

Write-Output "Pulling Review APP verifying the creation status..."
$maxTimeToWaitInSeconds = 1200 # 20 min
$createdAt = [datetime]::Now
$reviewAppInstanceID = $reviewAppInstance.id
$uri = "$herokuApiBaseURL/review-apps/$reviewAppInstanceID"
while(@("created", "errored") -inotcontains $reviewAppInstance.status -and  ([datetime]::Now - $createdAt).TotalSeconds -lt $maxTimeToWaitInSeconds){
    $reviewAppInstanceStatus = $reviewAppInstance.status
    Write-Output "Review APP status: $reviewAppInstanceStatus"
    sleep -Seconds 10
    try{
        # pull review app data to check the status
        $reviewAppInstance = Invoke-RestMethod -Method Get -Uri $uri  -Headers $herokuRequestHeader -Verbose -Debug
    }
    catch{

    }
}
Write-Output "*************************************************"
$completedWithError = $true
if($reviewAppInstance.status -eq "created"){
    $completedWithError = $false
    Write-Output "Primary Review APP was created successfully."
    Write-Output "URL: $reviewAppURL"
}
elseif($reviewAppInstance.status -eq "errored"){
    Write-Warning "Primary Review APP was not created."
}
else{
    Write-Warning "OPS!. The Primary Review APP is taking too long to be created. Process will completed without know if it was created or not. Please contact your admins to see details."
}

Write-Output "Review APP details: "
Write-Output $reviewAppInstance | ConvertTo-Json -Depth 10

if($completedWithError){
     throw("Unexpected Error while creating the Primary HEROKU Review APP.")
}

Write-Output "*************************************************"

Write-Output "====  END - Script of the Primary Heroku Review APP ==="



