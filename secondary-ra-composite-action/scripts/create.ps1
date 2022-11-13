 param (
    [Parameter(Mandatory=$true)]
    [string]$workingDirectoryPath,

    [Parameter(Mandatory=$true)]
    [string]$herokuApiKey,

    [Parameter(Mandatory=$true)]
    [string]$githubAccessToken,

    [Parameter(Mandatory=$true)]
    [string]$pullRequestNumber,

    [Parameter(Mandatory=$true)]
    [string]$herokuPipelineName,

    [Parameter(Mandatory=$true)]
    [string]$primaryReviewAppURL,

    [Parameter(Mandatory=$false)]
    [string]$environmentValues = "",

    [Parameter(Mandatory=$true)]
    [string]$githubRepositoryFullName,

    [Parameter(Mandatory=$true)]
    [string]$githubDefaultBranch,

    [Parameter(Mandatory=$true)]
    [string]$reviewAppURL,

    [Parameter(Mandatory=$true)]
    [string]$githubNewBranchPrefix
)

Write-Output "====  Beginning - Script of the Secondary HEROKU Review APP  ==="


# variables
$herokuApiBaseURL = "https://api.heroku.com"
# name of the repository with the source code of the secondary app. full name is owner/repo, so we are using the split functionality to get only last part
$secondarySourceRepositoryName = ("$githubRepositoryFullName".split('/'))[1]
# name of the branch we will create later.
$targetBranchName = [string]::Format("{0}{1}", $githubNewBranchPrefix, $pullRequestNumber)

# remove the local copy of the secondary repository if exists
if((Test-Path -Path $secondarySourceRepositoryName) -eq $true){
    Remove-Item -Path $secondarySourceRepositoryName -Force -Recurse
}

# create a new branch for the secondary Review App based on the githubDefaultBranch
write-output "Creating a new branch based on the branch '$githubDefaultBranch' of the repository $githubRepositoryFullName ..."
Write-Output "Cloning branch '$githubDefaultBranch'"
git clone -b $githubDefaultBranch "https://user:$githubAccessToken@github.com/$githubRepositoryFullName.git"
cd $secondarySourceRepositoryName

Write-Output "Verifying if the branch: '$targetBranchName' already exists in the repository $githubRepositoryFullName "
if((git ls-remote --heads origin  $targetBranchName)){
    Write-Output "Branch: '$targetBranchName' found. Removing it ..."
    git push origin --delete $targetBranchName
}

Write-Output "Creating branch: '$targetBranchName' ..."
git checkout -b $targetBranchName -f
git push origin $targetBranchName
Write-Output "Branch: '$targetBranchName' Created."
# set variable sourceVersion to the sha of the las commit to the target branch which is the branch we just created
$sourceCodeVersion = @(git rev-parse origin $targetBranchName)[0]
Write-Output "**************```***********************************"

# heroku request header definition
$herokuRequestHeader = @{
    "Authorization" = "Bearer $herokuApiKey"
    "Content-Type" = "application/json"
    "Accept" = "application/vnd.heroku+json;version=3"
}

# verify if secondary heroku pipeline exists
$herokuPipelineInstance = $null
$uri = "$herokuApiBaseURL/pipelines/$herokuPipelineName"
try{
    Write-Output "Getting secondary HEROKU pipeline details..."
    Write-Output "GET Request URL: $uri"
    $herokuPipelineInstance = Invoke-RestMethod -Method Get -Uri $uri -Headers $herokuRequestHeader -Verbose -Debug
    Write-Output $herokuPipelineInstance
}
catch{
    $exceptionMessage = $_.Exception.Message
    Write-Output $exceptionMessage
    Write-Output $_.ErrorDetails
    if($exceptionMessage -imatch "Not Found"){
        throw("Secondary HEROKU Pipeline Not Found. Please verify that the provided pipeline name is correct.")
    }
    else{
        throw("Unexpected Error. $exceptionMessage.")
    }
}
Write-Output "*************************************************"


# verify if exists already a review app
Write-Output "Verify if exists already a review app based on the branch '$targetBranchName' ..."
$herokuPipelineInstanceID = $herokuPipelineInstance.id
$uri = "$herokuApiBaseURL/pipelines/$herokuPipelineInstanceID/review-apps"

$appReviewList = Invoke-RestMethod -Method Get -Uri $uri -Headers $herokuRequestHeader -Verbose -Debug
Write-Output "GET Request URL: $uri"
$reviewAppInstances = $appReviewList.where{$_.branch.trim() -eq $targetBranchName}
if($reviewAppInstances.count -gt 0){
    Write-Warning "The pipeline: $herokuPipelineName has $($reviewAppInstances.count) Review APP based on the branch: $targetBranchName."
    Write-Output "Preparing to remove all of them..."
    foreach($instance in $reviewAppInstances){
        Write-Output "Removing Review App with ID: $($instance.id)..."
        $uri = "$herokuApiBaseURL/review-apps/$($instance.id)"
        Write-Output "DELETE Request URL: $uri"
        Invoke-RestMethod -Method Delete -Uri $uri -Headers $herokuRequestHeader -Verbose -Debug
        Write-Output "----------------------------------------------------."
    }
    # set up an sleep time.
    sleep -Seconds 30
    Write-Output "All review apps were removed."
}
else{
    Write-Output "Review APP Not Found."
}

Write-Output "*************************************************"

# github request header definition
$githubRequestHeader = @{
    Accept = "application/vnd.github+json"
    Authorization = "token $githubAccessToken"
}

# download the source code of the created branch $targetBranchName.
Write-Output "Downloading the source code of the branch $targetBranchName from github..."
$uri = "https://api.github.com/repos/$githubRepositoryFullName/tarball/$targetBranchName"
Write-Output "GET Request URL: $uri"
$sourceCodeFileName = $githubRepositoryFullName.Replace('/', '___') + "$targetBranchName.tgz"
$sourceCodeDownloadPath = "$workingDirectoryPath/$sourceCodeFileName"
try{
    Invoke-RestMethod -Uri $uri -Headers $githubRequestHeader -Method Get -OutFile $sourceCodeDownloadPath -Verbose -Debug | Out-Null
    Write-Output "Source Code Found."
    Write-Output "Downloading Path: $sourceCodeDownloadPath"
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
# so far only ensure that the BACKEND_URL configuration is present
Write-Output "Setting up the default environment variable values for the Primary Review App.."
$environmentValuesAsObject = [PSCustomObject]@{}
if(![string]::IsNullOrWhiteSpace($environmentValues)){
    $environmentValuesAsObject = $environmentValues | ConvertFrom-Json
}
$environmentValuesAsObject | Add-Member -MemberType NoteProperty -Name 'API_URL' -Value $primaryReviewAppURL  -Force
$environmentValuesAsObject | Add-Member -MemberType NoteProperty -Name 'BACKEND_URL' -Value $primaryReviewAppURL  -Force
$environmentValuesAsObject | Add-Member -MemberType NoteProperty -Name 'CORE_URL' -Value $primaryReviewAppURL  -Force
$environmentValuesAsObject | Add-Member -MemberType NoteProperty -Name 'WHIPLASH_API_URL' -Value $primaryReviewAppURL  -Force
Write-Output $environmentValuesAsObject

Write-Output "*************************************************"

Write-Output "Creating review app..."
# request body
$createReviewAppRequestBody = @{
  branch = $targetBranchName
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

Write-Output "Pulling details verifying the creation status..."
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
    Write-Output "Review APP was created successfully."
    Write-Output "URL: $reviewAppURL"
}
elseif($reviewAppInstance.status -eq "errored"){
    Write-Warning "Review APP was not created."
}
else{
    Write-Warning "OPS!. The Review APP is taking too long to be created. Process will completed without know if it was created or not. Please contact your admins to see details."
}

Write-Output "Review APP details: "
Write-Output $reviewAppInstance | ConvertTo-Json -Depth 10

if($completedWithError){
     throw("Unexpected Error while creating the HEROKU Review APP.")
}

Write-Output "*************************************************"

Write-Output "====  END - Script of the Secondary HEROKU Review APP ==="



