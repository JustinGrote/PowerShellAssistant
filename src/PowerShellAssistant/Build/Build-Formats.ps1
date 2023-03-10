#requires -module EzOut
param(
	[Parameter(Mandatory)]$SettingsPath,
	[Parameter(Mandatory)]$Destination
)

$tableProperties = Import-PowerShellDataFile $SettingsPath

foreach ($kv in $tableProperties.GetEnumerator()) {
	$outPath = Join-Path $Destination, 'Formats' $($kv.Name + '.Format.ps1xml')
	Write-FormatTableView -ViewTypeName $kv.Name -Property $kv.Value -AutoSize
	| Out-File -Force $outPath
}