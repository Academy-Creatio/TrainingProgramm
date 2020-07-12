param($AppName, $ZipPath, $ServerInstance, $dbUser, $port, $redisDbNum)
#Step 1 - Create Directory for new Installation
$AppPath = "C:\inetpub\wwwroot\$AppName"
New-Item -ItemType directory -Path $AppPath -Force
Write-Host "`nNEW $AppPath DIRECTORY CREATED " -ForegroundColor Green

#Step2 - Extract zip to $AppPath Folder
#Write-Host "Starting to unzip the application files to $AppPath, this might take a while" 
Expand-Archive -LiteralPath $ZipPath -DestinationPath $AppPath
Write-Host "UNPACKED APPLICATION FILES" -ForegroundColor Green

#Restoring DataBase
Write-Host "Started Restoring DataBase"
$DbPath = "$AppPath\db"
$dbFile = Get-ChildItem $DbPath | Where-Object {$_.FullName -match ".bak$"}

$mdf = 'C:\Program Files\Microsoft SQL Server\MSSQL14.SQLEXPRESS\MSSQL\DATA\'+$dbFile.BaseName+'.mdf'
$ldf = 'C:\Program Files\Microsoft SQL Server\MSSQL14.SQLEXPRESS\MSSQL\DATA\'+$dbFile.BaseName+'.ldf'
$fileName = $dbFile.FullName

# Prepare restore Query
$query = "USE [master] RESTORE DATABASE [$AppName] `
FROM  DISK = N'$fileName' WITH  FILE = 1, `
MOVE N'TSOnline_Data' TO N'$mdf', MOVE N'TSOnline_Log' TO N'$ldf', NOUNLOAD,  STATS = 5 `
GO"
# Execute Restore Query
Invoke-Sqlcmd -Query $query -ServerInstance $ServerInstance
Write-Host "`nDATABASE RESTORED:"-ForegroundColor Green

#Create db user
$dbuserQuery = "if not Exists (select loginname from master.dbo.syslogins where name = '$dbUser')`
Begin`
	declare @SqlStatement as nvarchar(max) = 'USE [master]'`
	EXEC sp_executesql @SqlStatement`
	select @SqlStatement = 'CREATE LOGIN [Creatio] WITH PASSWORD=N'+'''Supervisor'''+', DEFAULT_DATABASE=[master], CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF'`
	EXEC sp_executesql @SqlStatement`
End
"
Invoke-Sqlcmd -Query $dbuserQuery -ServerInstance $ServerInstance
Write-Host "`nCHECKING DATABASE USER:"-ForegroundColor Green


#prep Permission Query
$permQuery = "USE [$AppName] `
GO`
CREATE USER [$dbUser] FOR LOGIN [$dbUser]`
GO`
USE [$AppName]`
GO`
ALTER ROLE [db_owner] ADD MEMBER [$dbUser]`
GO
"
Invoke-Sqlcmd -Query $permQuery -ServerInstance $ServerInstance
Write-Host "`nGRANTED DB_OWNER ROLE TO DATABASE USER:"-ForegroundColor Green

#Edit ConnectionString.config file
# Replace Redis
$cs = "$AppPath\ConnectionStrings.config"
$con = Get-Content $cs
$myHost = iex 'hostname'
$con | % { $_.Replace("host=TSAGENT-2-6;db=0;port=6379", "host=$myHost;db=3;port=6379;maxReadPoolSize=10;maxWritePoolSize=500") } | Set-Content $cs

#Replace db
$cs = "$AppPath\ConnectionStrings.config"
$con = Get-Content $cs
$con | % { $_.Replace("Data Source=TSAGENT-2-6;Initial Catalog=StudioENU_3364335_0626;Integrated Security=SSPI;MultipleActiveResultSets=True;Pooling=true;Max Pool Size=100", "Data Source=$ServerInstance;Initial Catalog=$AppName;User ID=$dbUser;Password=Supervisor;MultipleActiveResultSets=True;Pooling=true;Max Pool Size=100") } | Set-Content $cs
Write-Host "`nUPDATED CONNECTION STRING" -ForegroundColor Green


#IIS
# Create new webPool
New-WebAppPool -Name $AppName -Force

#Create IIS Site
New-WebSite -Name $AppName -Port $port -HostHeader localhost -PhysicalPath $AppPath -Force

# Add App
New-WebApplication -Name 0 -Site $Appname -ApplicationPool $AppName -PhysicalPath $AppPath"\Terrasoft.WebApp" -Force
Write-Host "IIS Site Created"
Write-Host "`nCREATED NEW SITE AND APP_POOL:"-ForegroundColor Green

#Open Application
Start-Process "http://localhost:$port"
Write-Host "`n!!! ENJOY YOUR CREATION !!!" -ForegroundColor Green

#Update clio to the latest version
iex 'dotnet tool update clio -g'

