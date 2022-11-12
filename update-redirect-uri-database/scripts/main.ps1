param (
    [Parameter(Mandatory=$true)]
    [string]$server,

    [Parameter(Mandatory=$true)]
    [string]$dbName,

    [Parameter(Mandatory=$true)]
    [string]$dbUser,

    [Parameter(Mandatory=$true)]
    [string]$dbPassword,

    [Parameter(Mandatory=$true)]
    [string]$redirectUri,

    [Parameter(Mandatory=$false)]
    [string]$mysqlDriverPath = "C:\Program Files (x86)\MySQL\*\Assemblies\v4.5.2\MySql.Data.dll"
)


if(!(Test-Path -Path $mysqlDriverPath)){
    throw("Invalid MySQL Driver Path. The path '$mysqlDriverPath' is wrong or missing.")
}
try{
    # load mysql driver
    Add-Type -Path $mysqlDriverPath

    Write-Output "Establishing a connection with the target server $server ..."
    $connection = [MySql.Data.MySqlClient.MySqlConnection]@{ConnectionString="server=$server;uid=$dbUser;pwd=$dbPassword;database=$dbName;SslMode=none;"}
    $connection.Open()
    Write-Output "Connection successfully."
    $sql = New-Object MySql.Data.MySqlClient.MySqlCommand
    $sql.Connection = $connection
    $query = "UPDATE oauth_applications t SET redirect_uri = CONCAT(t.redirect_uri, '\n' , ' $redirectUri') WHERE name = 'Rails Frontend' and locate('$redirectUri', t.redirect_uri) = 0;"
    $sql.CommandText = $query
    Write-Output "Updating the 'redirect_uri' column of the table 'oauth_applications' with the new Redirect URI ..."
    $sql.ExecuteNonQuery()
    Write-Output "update completed."
    Write-Output "Closing the connection ..."
    $connection.Close()
    Write-Output "Connection closed."

    Write-Output "********** DONE ***********"
}
catch{
    Write-Output "Unexpected Error. It was not possible to update the redirect uri with the new value due to an error."
    throw($_.Exception.Message)
}
