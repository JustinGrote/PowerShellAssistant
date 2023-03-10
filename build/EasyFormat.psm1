using namespace System.Management.Automation
using namespace System.Collections
function ConvertFrom-Format {
	<#
	.SYNOPSIS
		Converts Format-Table output to a format that can be used with Add-FormatTable
	#>
	param(
		#The name of the format view definition assigned to the format data. Default is 'CustomTableView
		[ValidateNotNullOrEmpty()][string]$Name = 'CustomTableView',
		#The format data to convert. It's best to pipe to this command from Format-Table, etc. for best results
		[Parameter(ValueFromPipeline)][object]$InputObject
	)

	begin {
		$ErrorActionPreference = 'Stop'
		New-Variable -Name 'FormatStartData'
	}
	process {
		#This is an internal type so we cannot use -is
		if (($InputObject.GetType().Name) -ne 'FormatStartData') {
			return
		}
		if ($FormatStartData) {
			Write-Warning 'Multiple formats detected, please pass only one format type to this function. It will only process the first format detected'
			return
		}
		$formatStartData = $InputObject
	}
	end {
		if (-not $formatStartData) {
			Write-Error 'You must provide formatting info to this command. Try | Format-Table | ConvertFrom-Format'
		}

		$shapeInfo = $formatStartData.shapeInfo
		if ($shapeInfo.HeaderInfo.count -gt 1) { throw 'Multiple Header Infos detected. This is a bug and should never happen.' }

		[PSControl]$control = switch ($shapeInfo.GetType().Name) {
			'TableHeaderInfo' {
				New-TableControl $shapeInfo
			}
			default { throw [System.NotImplementedException]'This type of format is not supported yet' }
		}

		return [FormatViewDefinition]::new($Name, $control)
	}
}

filter Add-TypeFormat {
	<#
	.SYNOPSIS
	Adds a new format view definition to the current session state
	#>
	[CmdletBinding()]
	param(
		#Supply an object or type definition to add the format definition to the corresponding type
		[Parameter(Mandatory)][Object]$Type,
		[Parameter(Mandatory, ValueFromPipeline)]
		[Management.Automation.FormatViewDefinition]$FormatViewDefinition,
		#Do not Persist the changes to the current session state. This is useful if you want to add multiple format definitions to a type and then Persist them all at once. Assumes -NoUpdate
		[switch]$NoPersist,
		#Update the definitions but do not process them. You should rarely need to do this, maybe if adding a lot of type definitions at runtime amd then update them separately
		[switch]$NoUpdate
	)

	$ErrorActionPreference = 'Stop'
	if ($Type -is [PSCustomObject]) {
		throw [NotImplementedException]'This command does not yet support PSCustomObjects'
	}
	if ($Type -is [IEnumerable]) {
		throw [NotImplementedException]'Custom Types are not supported on collections/dictionaries/enumerables'
	}
	if ($Type.GetType().IsPrimitive) {
		throw [NotSupportedException]'Cannot add custom formats to primitive types'
	}

	[Reflection.TypeInfo]$TypeInfo = $Type -is [Reflection.TypeInfo] ? $Type : $Type.GetType()
	[ExtendedTypeDefinition]$formatData = Get-FormatData -TypeName $TypeInfo.FullName
	$formatData ??= [ExtendedTypeDefinition]::new($Type.FullName)

	#TODO: Conflict checking
	$formatData.FormatViewDefinition.Add($formatViewDefinition)
	[Runspace]::DefaultRunspace.InitialSessionState.Formats.Add($formatData)

	if (-not $NoUpdate) {
		Update-FormatData
	}
}

function New-TableControl {
	[OutputType([TableControl])]
	param($TableHeaderInfo) #Should be TableHeaderInfo

	[TableControl]$table = [TableControl]::new()
	[TableControlRow]$rowFormat = [TableControlRow]::new()

	#HACK: There is an additional objectCount property that is apparently not used in the translation
	$table.AutoSize = $null -ne $TableHeaderInfo.AutoSizeInfo
	$table.Rows = $rowFormat

	if ($TableHeaderInfo.tableColumnInfoList.count -le 0) { throw 'No table column info found' }
	foreach ($columnInfo in $TableHeaderInfo.tableColumnInfoList) {
		#This is a little confusing, but the row columns and the headers should almost always align. The display label is defined on the header and the actual property it references is defined in the column.
		#So for each property in the HeaderInfo, we create a new TableControlColumnHeader and TableControlColumn

		$columnHeader = [TableControlColumnHeader]::new($columnInfo.Label, $columnInfo.Width, $columnInfo.Alignment)
		$column = [TableControlColumn]::new($columnInfo.Alignment, [DisplayEntry]::new($columnInfo.propertyName,
				'Property'))

		$table.Headers.Add($columnHeader)
		$rowFormat.Columns.Add($column)
	}

	return $table
}

function Format-EasyTable {
	<#
	.SYNOPSIS
	With the same syntax as Format-Table, this command will Persist the format table to the current session state
	.ForwardHelpTargetName Microsoft.PowerShell.Utility\Format-Table
	.ForwardHelpCategory Cmdlet
	#>
	[CmdletBinding(HelpUri = 'https://go.microsoft.com/fwlink/?LinkID=2096703')]
	param(
		[switch]
		${AutoSize},

		[switch]
		${RepeatHeader},

		[switch]
		${HideTableHeaders},

		[switch]
		${Wrap},

		[Parameter(Position = 0)]
		[System.Object[]]
		${Property},

		[System.Object]
		${GroupBy},

		[string]
		${View},

		[switch]
		${ShowError},

		[switch]
		${DisplayError},

		[switch]
		${Force},

		[ValidateSet('CoreOnly', 'EnumOnly', 'Both')]
		[string]
		${Expand},

		[Parameter(ValueFromPipeline = $true)]
		[psobject]
		${InputObject},

		#Make this formatting "sticky" and persist it to the current session state
		[Parameter(ParameterSetName = 'Persist')][switch]$Persist,

		# The name of the format view definition assigned to the format data.
		[Parameter(ParameterSetName = 'Persist')][string]$FormatName,

		# Output the formatView to this variable name. Defaults to 'PersistFormatTableView'
		[Parameter(ParameterSetName = 'Persist')][ValidateNotNullOrEmpty()][string]$FormatOutVariable,

		# Output the xml representation of the format definition for the type. Implies -Persist.
		[Parameter(ParameterSetName = 'Persist')][ValidateNotNullOrEmpty()][string]$OutXml,

		# Don't update the format data. Useful if you just want to Persist to FormatOutVariable
		[Parameter(ParameterSetName = 'Persist')][switch]$NoUpdate
	)

	begin {
		$DoPersist = $PSCmdlet.ParameterSetName -eq 'Persist'
		try {
			$outBuffer = $null
			if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer)) {
				$PSBoundParameters['OutBuffer'] = 1
			}

			$wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Microsoft.PowerShell.Utility\Format-Table', [System.Management.Automation.CommandTypes]::Cmdlet)
			if ($DoPersist) {
				$firstObjectType = $null
				[ArrayList]$FormatData = @()
				'Persist', 'FormatName', 'FormatOutVariable', 'NoUpdate'
				| ForEach-Object {
					[void]$PSBoundParameters.Remove($PSItem)
				}
			}

			$scriptCmd = { & $wrappedCmd @PSBoundParameters }
			$steppablePipeline = $scriptCmd.GetSteppablePipeline($myInvocation.CommandOrigin)
			$steppablePipeline.Begin($MyInvocation.ExpectingInput)
		} catch {
			throw
		}
	}

	process {
		try {
			$firstObjectType = $_.GetType()
			$processOutput = $steppablePipeline.Process($_)
			if ($DoPersist) {
				$processOutput.Foreach{
					[void]$FormatData.Add($PSItem)
				}
			}
			$processOutput
		} catch {
			throw
		}
	}

	end {
		try {
			#We currently don't care about the end data
			$steppablePipeline.End()

			if ($DoPersist) {
				$ErrorActionPreference = 'Stop'
				$formatDefinition = $FormatData | ConvertFrom-Format -ErrorAction Stop
				if ($FormatOutVariable) {
					#HACK: This probably should be better scoped to where the command was invoked
					Set-Variable -Scope Global -Name $FormatOutVariable -Value $formatDefinition -Force
				}
				if (-not $NoPersist) {
					Add-TypeFormat -Type $firstObjectType -FormatViewDefinition $formatDefinition -NoUpdate:$NoUpdate
				}
			}
		} catch {
			throw
		}
	}

	clean {
		if ($null -ne $steppablePipeline) {
			$steppablePipeline.Clean()
		}
	}
}


#region Private
function Add-CalculatedProperties ([object]$Properties) {

	#TODO: In order to do this we have to update the typedata.
	# foreach ($Property in $Properties) {
	# 	if ($Property -is [Scriptblock]) {
	# 		throw [NotSupportedException]'Raw Scriptblocks in -Properties are not supported'
	# 	}
	# 	if ($Property -is [string]) {
	# 		#This has already been handled by Format-Table, there's nothing to include
	# 		continue
	# 	}
	# 	if ($Property -isnot [hashtable]) {
	# 		Write-Warning "$($Property.GetType()) is not currently implemented for parsing in -Properties and will be ignored"
	# 	}

	# 	foreach ($key in $Property.keys) {
	# 		$NameSpecified = $false
	# 		switch -Wildcard ($key) {
	# 			'N*' {
	# 				$NameSpecified = $true
	# 			}
	# 			'default' {
	# 				Write-Warning "$key is not a currently implemented key for a calculated property in -Properties and will be ignored"
	# 				continue
	# 			}
	# 		}

	# 		if (-not $NameSpecified) {
	# 			Write-Warning 'The Name key was not included in one of the calculated properties. That property will be ignoread'
	# 			continue
	# 		}

	# 	}
	# }
}

#endregion Private