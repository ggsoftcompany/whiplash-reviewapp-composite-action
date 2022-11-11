 param (
    [Parameter(Mandatory=$true)]
    [string]$pullRequestNumber,

    [Parameter(Mandatory=$true)]
    [string]$reviewappPrefixURL,

    [Parameter(Mandatory=$true)]
    [string]$secondaryReviewappPrefixURL,

    [Parameter(Mandatory=$true)]
    [string]$secondaryReviewappNewBranchPrefix
)

Write-Output "====  Beginning - Generate Urls script  ==="


Write-Output "Setting up the primary reviewapp URL..."
# set a variable with the projected URL for the Primary review App.
# this variable will be used in post scripts
$reviewAppURL = "https://$reviewAppPrefixURL-pr-$pullRequestNumber.herokuapp.com"
Write-Output "URL: $reviewAppURL"
echo "reviewapp_URL=$($reviewAppURL)" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
Write-Output "Primary reviewapp URL completed"

Write-Output "*************************************************"

Write-Output "Setting up the secondary reviewapp URL..."
# set a variable with the projected URL for the Secondary review App.
$secondaryReviewAppTargetBranchName = [string]::Format("{0}{1}", $secondaryReviewAppNewBranchPrefix, $pullRequestNumber)
$secondaryReviewAppURL = "https://$secondaryReviewAppPrefixURL-br-$secondaryReviewAppTargetBranchName.herokuapp.com"
Write-Output "URL: $secondaryReviewAppURL"
echo "secondaryReviewapp_URL=$($secondaryReviewAppURL)" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
Write-Output "Secondary reviewapp URL completed"

Write-Output "====  END - Generate Urls script ==="
