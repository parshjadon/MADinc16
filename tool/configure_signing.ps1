$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskPrivate = Join-Path $taskRoot 'private'
New-Item -ItemType Directory -Force -Path $taskPrivate | Out-Null
$keyStore = Join-Path $taskPrivate 'science-signal-release.jks'
if (Test-Path -LiteralPath $keyStore) { Write-Output 'Release signing key already exists.'; exit 0 }
$keyBytes = New-Object byte[] 32
$randomSource = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$randomSource.GetBytes($keyBytes)
$randomSource.Dispose()
$keyPassword = [Convert]::ToBase64String($keyBytes)
$javaHome = if ($env:JAVA_HOME) { $env:JAVA_HOME } else { 'C:\MAD\Andriod Studio\jbr' }
& (Join-Path $javaHome 'bin\keytool.exe') -genkeypair -keystore $keyStore -alias science-signal -keyalg RSA -keysize 2048 -validity 3650 -storepass $keyPassword -keypass $keyPassword -dname 'CN=Parsh Jadon, OU=ICA16 Class B, O=Science Signal, C=US'
if ($LASTEXITCODE -ne 0) { throw 'Key generation failed.' }
$properties = "storePassword=$keyPassword`nkeyPassword=$keyPassword`nkeyAlias=science-signal`nstoreFile=../../private/science-signal-release.jks`n"
[IO.File]::WriteAllText((Join-Path $taskRoot 'android\key.properties'), $properties)
Write-Output 'Private release signing configured. Key and passwords are excluded from Git.'
