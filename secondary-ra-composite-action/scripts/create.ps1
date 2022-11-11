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
# set variable secondaryReviewAppSourceVersion to the sha of the las commit to the target branch which is the branch we just created
$secondaryReviewAppSourceVersion = @(git rev-parse origin $targetBranchName)
Write-Output "*************************************************"

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


# verify if exists already a review app related with the $targetBranchName
Write-Output "Verify if exists already a review app based on the branch '$targetBranchName' ..."
$herokuPipelineInstanceID = $herokuPipelineInstance.id
$uri = "$herokuApiBaseURL/pipelines/$herokuPipelineInstanceID/review-apps"

$appReviewList = Invoke-RestMethod -Method Get -Uri $uri -Headers $herokuRequestHeader -Verbose -Debug
Write-Output "GET Request URL: $uri"
$reviewAppInstances = $appReviewList.where{$_.branch.trim() -eq $targetBranchName -or $_.pr_number -eq $pullRequestNumber}
if($reviewAppInstances.count -gt 0){
    Write-Warning "The pipeline: $herokuPipelineName has $($reviewAppInstances.count) Review APP based on the branch: $targetBranchName."
    Write-Output "Preparing to remove all of them..."
    foreach($instance in $reviewAppInstances){
        Write-Output "Removing Review App with ID: $($instance.id)..."
        $uri = "$herokuApiBaseURL/review-apps/$($instance.id)"
        Invoke-RestMethod -Method Delete -Uri $uri -Headers $herokuRequestHeader -Verbose -Debug
        Write-Output "DELETE Request URL: $uri"
        Write-Output "Review App with ID: $($instance.id) was removed."
    }
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


Write-Output "====  END - Script of the Secondary HEROKU Review APP ==="



