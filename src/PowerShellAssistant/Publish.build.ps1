#requires -module InvokeBuild
param(
	$Destination = $(Resolve-Path (Join-Path $PSScriptRoot '..\..\dist')),
	$FormatSettingsPath = $(Join-Path $PSScriptRoot 'FormatSettings.settings.ps1')
)

Task Formats {
	Import-Module EzOut -ErrorAction Stop

	$formatPath = Join-Path $Destination 'Formats'
	New-Item -ItemType Directory -Force -Path $formatPath | Out-Null

	[hashtable]$tableProperties = . $formatSettingsPath

	$formatFilePaths = foreach ($kv in $tableProperties.GetEnumerator()) {
		$typeName = $kv.Name
		$outPath = Join-Path $formatPath $($typeName + '.Format.ps1xml')
		$setting = $kv.Value

		switch ($setting.GetType()) {
			([string]) {
				Write-FormatView -TypeName $typeName -Property $kv.Value -AutoSize
				| Out-FormatData
				| Out-File -Force $outPath
			}
			([object[]]) {
				Write-FormatView -TypeName $typeName -Property $kv.Value -AutoSize
				| Out-FormatData
				| Out-File -Force $outPath
			}
			([ScriptBlock]) {
				Write-FormatView -TypeName $typeName -Action $setting
				| Out-FormatData
				| Out-File -Force $outPath
			}
			([hashtable]) {
				throw [NotImplementedException]'TODO: Hashtable not implemented. It will allow select-style expressions to create virtual properties'
			}
			default {
				throw [NotSupportedException]"Unsupported format setting value type: $($setting.GetType())"
			}
		}
		[IO.Path]::GetRelativePath($Destination, $outPath)
	}
	Update-ModuleManifest -Path $Destination/PowerShellAssistant.psd1 -FormatsToProcess $formatFilePaths
}

Task . Formats