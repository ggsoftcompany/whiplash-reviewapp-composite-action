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
    [string]$herokuPipelineName
)


# variables
$herokuApiBaseURL = "https://api.heroku.com"
$pullRequestNumber = $githubFullBranchName.Replace("refs/pull/", "").Replace("/merge", "").trim()
$branchName = $githubFullBranchName.Replace("refs/", "").trim()

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
    #echo "##vso[task.setvariable variable=ReviewAppExists;isOutput=true]Yes" #set variable
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



write-output "== DONE =="
