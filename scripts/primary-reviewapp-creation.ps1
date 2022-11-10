 param (
    [Parameter(Mandatory=$false)]
    [string]$workingDirectoryPath = "lola"
)

write-output "Working directory: $workingDirectoryPath"
write-output "github-pat: ${{ inputs.github-pat }}"

write-output "== DONE =="
