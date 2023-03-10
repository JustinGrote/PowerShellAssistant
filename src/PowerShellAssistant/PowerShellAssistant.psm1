using namespace OpenAI
using namespace System.Net.Http
using namespace System.Net.Http.Headers
using namespace System.Collections.Generic
using namespace System.Management.Automation

$ErrorActionPreference = 'Stop'
Add-Type -Path (Join-Path $PSScriptRoot '*.dll')

#This is the cheapest model for testing
$SCRIPT:aiDefaultModel = 'ada'
$SCRIPT:aiDefaultChatModel = 'gpt-3.5-turbo'

#region Public
function Connect-AI {
	[CmdletBinding()]
	param(
		# Provide your API Key as the password, and optionally your organization ID as the username
		[string]$APIKey,

		# By default, this uses the OpenAI API. Specify this if you want to use GitHub Copilot (UNSUPPORTED)
		[switch]$GitHubCopilot,

		# Don't set this client as the default client. You can pass the client to the various commands instead. Implies -PassThru
		[switch]$NoDefault,

		# Return the client for use in other commands
		[switch]$PassThru,

		#Replace the existing default client if it exists
		[switch]$Force
	)
	if ($SCRIPT:aiClient -and (-not $NoDefault -and -not $Force)) {
		Write-Warning 'Already connected to an AI engine. You can use -NoDefault to not set this client as the default client, or -Force to replace the existing default client.'
		return
	}

	if (-not $APIKey -and $env:OPENAI_API_KEY) {
		Write-Verbose 'Using API key from environment variable OPENAI_API_KEY'
		$APIKey = $env:OPENAI_API_KEY
	}

	$client = New-AIClient @newAIClientParams -APIKey $APIKey

	if (-not $NoDefault) {
		$SCRIPT:aiClient = $client
	}

	if ($PassThru) {
		return $client
	}
}

filter Get-AIModel {
	[OutputType([OpenAI.Model])]
	[CmdletBinding()]
	param(
		# The ID of the model to get. If not specified, returns all models.
		[Parameter(ValueFromPipeline)][string]$Id,
		[ValidateNotNullOrEmpty()][OpenAI.Client]$Client = $SCRIPT:aiClient
	)
	if (-not $Client) {
		Assert-Connected
		$Client = $SCRIPT:aiClient
	}

	if ($Id) {
		return $Client.RetrieveModel($Id)
	}

	$Client.ListModels().Data
}


function Get-AIEngine {
	[OutputType([OpenAI.Engine])]
	[CmdletBinding()]
	param(
		[ValidateNotNullOrEmpty()][OpenAI.Client]$Client = $SCRIPT:aiClient
	)
	Write-Warning 'Engines are deprecated. Use Get-AIModel instead.'
	if (-not $Client) {
		Assert-Connected
		$Client = $SCRIPT:aiClient
	}

	$Client.ListEngines()
	| ConvertFrom-ListResponse
}

function Get-AICompletion {
	[CmdletBinding()]
	[OutputType([OpenAI.CreateCompletionResponse])]
	param(
		[Parameter(Mandatory)]$Prompt,
		#The name of the model to use.
		[ValidateSet([AvailableModels])][String]$Model = $SCRIPT:aiDefaultModel,
		[ValidateNotNullOrEmpty()][OpenAI.Client]$Client = $SCRIPT:aiClient,
		[ValidateNotNullOrEmpty()][uint]$MaxTokens = 1000,
		[ValidateNotNullOrEmpty()][uint]$Temperature = 0
	)
	if (-not $Client) {
		Assert-Connected
		$Client = $SCRIPT:aiClient
	}

	$request = [CreateCompletionRequest]@{
		Prompt      = $Prompt
		Stream      = $false
		Model       = $Model
		Max_tokens  = $MaxTokens
		Temperature = $Temperature
	}
	$Client.CreateCompletion($request)
}

function Get-AIChat {
	[CmdletBinding()]
	[OutputType([OpenAI.CreateChatCompletionResponse])]
	param(
		#Include one or more prompts to start the conversation
		[Parameter(Mandatory)]
		[string[]]$Prompt,

		#Supply a previous chat session to add new responses to it
		[OpenAI.CreateChatCompletionRequest]$ChatSession,

		#Save the chat session to this variable, so you can add more responses to it later
		[string]$SessionVariable,


		#The name of the model to use.
		[ValidateSet([AvailableModels])]
		[String]$Model = $SCRIPT:aiDefaultChatModel,

		[ValidateNotNullOrEmpty()]
		[OpenAI.Client]$Client = $SCRIPT:aiClient,

		[ValidateNotNullOrEmpty()]
		[uint]$MaxTokens = 1000,

		[ValidateNotNullOrEmpty()]
		[uint]$Temperature = 0
	)
	if (-not $Client) {
		Assert-Connected
		$Client = $SCRIPT:aiClient
	}

	$ChatSession ??= [CreateChatCompletionRequest]@{
		Messages    = [List[ChatCompletionRequestMessage]]@()
		Stream      = $false
		Model       = $Model
		Max_tokens  = $MaxTokens
		Temperature = $Temperature
	}

	foreach ($PromptItem in $Prompt) {
		$ChatSession.Messages.Add(
			[ChatCompletionRequestMessage]@{
				Content = $PromptItem
				#BUG: This is case sensitive in the API but NSWag generates it as uppercase
				Role    = 'user'
			}
		)
	}

	$chatResponse = $Client.CreateChatCompletion($ChatSession)

	if ($SessionVariable) {
		#TODO: Implement Session Variable
		throw [System.NotImplementedException]('NOT IMPLEMENTED: Needs to find which messages are new and add them to the session variable.')
	}

	return $chatResponse
}
#endregion Public

#Region Private
function New-AIClient {
	[OutputType([OpenAI.Client])]
	param(
		[string]$ApiKey,
		[Switch]$GithubCopilot
	)

	if (-not $APIKey) {
		Write-Error 'You must supply an OpenAI API key via the -APIKey parameter or by setting the OPENAI_API_KEY variable'
		return
	}

	if ($SCRIPT:client -and -not $Force) {
		Write-Warning 'Assistant is already connected. Please use -Force to reset the client.'
		return
	}
	$httpClient = [HttpClient]::new()
	$httpClient.DefaultRequestHeaders.Authorization = [AuthenticationHeaderValue]::new('Bearer', $APIKey)

	$aiClient = [Client]::new($httpClient)

	if ($GitHubCopilot) {
		$aiClient.BaseUrl = 'https://copilot-proxy.githubusercontent.com'
	}

	return $aiClient
}

function Assert-Connected {
	if (-not $SCRIPT:aiClient) {
		Connect-AI
	}
}

#If the returned result was a list, return the actual data
filter ConvertFrom-ListResponse {
	if ($PSItem.Object -ne 'list') { return }
	return $PSItem.Data
}



#endregion Private


# function Connect-Copilot {
# 	[CmdletBinding()]
# 	param(
# 		# Provide your Copilot API Key as the password, and optionally your organization ID as the username
# 		[string]$Token,

# 		#Reset if a client already exists
# 		[Switch]$Force
# 	)
# 	$ErrorActionPreference = 'Stop'

# 	if ($SCRIPT:GHClient -and -not $Force) {
# 		Write-Warning 'Copilot is already connected. Please use -Force to reset the client.'
# 		return
# 	}

# 	if ($SCRIPT:GHCopilotToken -and -not $Force) {
# 		Write-Warning 'GitHub Copilot is already connected. Please use -Force to reset the client.'
# 		return
# 	}

# 	$SCRIPT:GHCopilotToken = if (-not $Token) {
# 		#Try to autodiscover it from GitHub Copilot CLI
# 		if (-not (Test-Path $HOME/.copilot-cli-access-token)) {
# 			Write-Error "To use PowerShell Assistant with GitHub Copilot, you must install GitHub Copilot CLI and run 'github-copilot-cli auth' at least once to generate a Copilot Personal Access Token (PAT)"
# 			return
# 		}
# 		Get-Content $HOME/.copilot-cli-access-token
# 	} else {
# 		$Token
# 	}

# 	$config = [OpenAIOptions]@{
# 		ApiKey          = Update-GitHubCopilotToken $SCRIPT:GHCopilotToken
# 		BaseDomain      = 'https://copilot-proxy.githubusercontent.com'
# 		DefaultEngineId = 'copilot-labs-codex'
# 	}

# 	$SCRIPT:GHClient = [OpenAIService]::new($config)
# }

# function Get-CopilotSuggestion {
# 	[CmdletBinding()]
# 	param(
# 		[Parameter(Mandatory)][string]$prompt,
# 		[ValidateNotNullOrEmpty()]$client = $SCRIPT:GHClient
# 	)

# 	if (-not $SCRIPT:GHClient) { Connect-Copilot }
# 	$request = [CompletionCreateRequest]@{
# 		N           = 1
# 		StopAsList  = [string[]]@('---', '\n')
# 		MaxTokens   = 256
# 		Temperature = 0
# 		TopP        = 1
# 		Prompt      = $prompt
# 		Stream      = $true
# 	}
# 	$resultStream = $client.Completions.CreateCompletionAsStream($request).GetAwaiter.GetResult()
# 	foreach ($resultItem in $resultStream) {
# 		Write-Host -NoNewline 'NEW TOKEN'
# 		#This gives us intellisense in vscode
# 		[CompletionCreateResponse]$result = $resultItem
# 		if ($result.Error) {
# 			Write-Error $result.Error
# 			return
# 		}
# 		$token = $result.Choices[0].Text
# 		Write-Host -NoNewline -fore DarkGray $token
# 	}
# 	Write-Host 'DONE'
# }


# function Assert-Connected {
# 	if (-not $SCRIPT:client) { Connect-Assistant }
# }

# function Update-GitHubCopilotToken {
# 	<#
# 	.SYNOPSIS
# 	Fetches the latest token for GitHub Copilot
# 	#>
# 	param(
# 		[ValidateNotNullOrEmpty()]
# 		$GitHubToken = $SCRIPT:GHCopilotToken
# 	)
# 	$ErrorActionPreference = 'Stop'
# 	$response = Invoke-RestMethod 'https://api.github.com/copilot_internal/v2/token' -Headers @{
# 		Authorization = "token $($GitHubToken.trim())"
# 	}
# 	return $response.token
# }

# function Get-Chat {
# 	[CmdletBinding()]
# 	param(
# 		#Provide a chat prompt to initiate the conversation
# 		[string[]]$chatPrompt,

# 		#If you just want the result and don't want to be prompted for further replies, specify this
# 		[Switch]$NoReply,

# 		#By default, the latest code recommendation is copied to your clipboard, specify this to disable the behavior
# 		[switch]$NoClipboard,

# 		[ValidateNotNullOrEmpty()]
# 		#Specify a prompt that guides Chat how to behave. By default, it is told to prefer PowerShell as a language.
# 		[string]$SystemPrompt = 'PowerShell syntax and be brief',

# 		#Maximum tokens to generate. Defaults to 500 to minimize accidental API billing
# 		[ValidateNotNullOrEmpty()]
# 		[uint]$MaxTokens = 500,

# 		[ValidateNotNullOrEmpty()]
# 		[string]$Model = [Models]::ChatGpt3_5Turbo
# 		#TODO: Figure out how to autocomplete this
# 	)
# 	begin {
# 		$ErrorActionPreference = 'Stop'
# 		Assert-Connected
# 		[List[ChatMessage]]$chatHistory = @(
# 			[ChatMessage]::FromSystem($SystemPrompt)
# 		)
# 	}
# 	process {
# 		do {
# 			$chatPrompt ??= Read-Host -Prompt 'You'
# 			$chatHistory.Add(
# 				[ChatMessage]::FromUser($chatPrompt)
# 			)
# 			$request = [ChatCompletionCreateRequest]@{
# 				Messages  = $chatHistory
# 				MaxTokens = $MaxTokens
# 				Model     = $Model
# 			}

# 			#TODO: Loop this and make it cancellable
# 			[ResponseModels.ChatCompletionCreateResponse]$response = $client.
# 			ChatCompletion.
# 			CreateCompletion($request).
# 			GetAwaiter().
# 			GetResult()

# 			if (-not $response.Successful) {
# 				$errCode = $response.Error.Code ?? 'UNKNOWN'
# 				$errMsg = $response.Error.Message ?? 'Unknown error'
# 				Write-Error "$errCode - $errMsg"
# 				return
# 			}

# 			$aiResponse = $response.Choices[0] ?? { throw new Exception('No response from AI. This is a probably a bug you should report.') }

# 			[string]$responseMessage = $aiResponse.Message.Content

# 			$chatHistory.Add(
# 				[ChatMessage]::FromAssistance($responseMessage)
# 			)

# 			$responseMessage
# 			| Convert-ChatCodeToClipboard
# 			| Format-ChatCode
# 			| Write-Host -Fore DarkGray

# 			#Handle various bugs that might occur
# 			if ($aiResponse.Message.Role -ne 'assistant') {
# 				Write-Warning 'Chat response was not from the assistant. This is a probably a bug you should report.'
# 			}

# 			switch ($aiResponse.FinishReason) {
# 				'stop' {} #This is the normal response
# 				'length' {
# 					Write-Warning "$MaxTokens tokens reached. Consider increasing the value of -MaxTokens for longer responses."
# 				}
# 				$null {
# 					Write-Debug 'Null FinishReason received. This seems to occur on occasion and may or may not be a bug.'
# 				}
# 				default {
# 					Write-Warning "Chat response finished abruply due to: $($aiResponse.FinishReason)"
# 				}
# 			}

# 			$chatPrompt = $null
# 			if (-not $NoReply) {
# 				Write-Host -Fore Cyan '<Ctrl-C to exit>'
# 			}
# 		} while (
# 			-not $NoReply
# 		)
# 	}
# }



# filter Convert-ChatCodeToClipboard {
# 	<#
# 	.SYNOPSIS
# 	Given a string, take the last occurance of text surrounded by a fenced code block, and copy it to the clipboard.
# 	It will also pass through the string for further filtering
# 	#>
# 	$fencedCodeBlockRegex = '(?s)```[\r|\n|powershell]+(.+?)```'
# 	$matchResult = $PSItem -match $fencedCodeBlockRegex
# 	$savedMatches = $matches
# 	$cbMatch = $savedMatches.($savedMatches.Keys | Sort-Object | Select-Object -Last 1)
# 	if (-not $matchResult) {
# 		Write-Debug 'No code block detected, skipping this step'
# 		return $PSItem
# 	}

# 	Write-Debug "Copying last suggested code block to clipboard:`n$cbMatch"
# 	Set-Clipboard -Value $cbMatch

# 	return $PSItem
# }

# filter Debug-APICost {
# 	<#
# 	.SYNOPSIS
# 	Parses the API info and calculates the approximate cost of the query.
# 	#>
# 	Write-Debug 'This query took 30 minutescls'
# }

class AvailableModels : IValidateSetValuesGenerator {
	[String[]] GetValidValues() {
		$models = Get-AIModel
		return $models.Id
	}
}

filter Format-ChatCode {
	<#
	.SYNOPSIS
	Given a string, for any occurance of text surrounded by backticks, replace the backticks with ANSI escape codes
	#>
	$codeBlockRegex = '(?s)```[\r|\n|powershell]+(.+?)```'
	$codeSnippetRegex = '(?s)`(.+?)`'
	$boldSelectedText = ($PSStyle.Italic + '$1' + $PSStyle.ItalicOff)
	$PSItem -replace $codeBlockRegex, $boldSelectedText -replace $codeSnippetRegex, $boldSelectedText
}

function Format-ChatCompletionResponseMessage {
	param(
		[OpenAI.ChatCompletionResponseMessage]$message
	)

	$role = $message.Role
	$roleColor = switch ($role) {
		'Assistant' { 'Green' }
		'User' { 'DarkCyan' }
		default { 'DarkGray' }
	}
	$formattedMessage = $message.Content.Trim() | Format-ChatCode
	"$($PSStyle.Foreground.$roleColor)$role`:$($PSStyle.Reset) $($PSStyle.ForeGround.BrightBlack)$formattedMessage"
}

function Format-Choices2 {
	param(
		[Choices2]$choice
	)
	$PSStyle.Foreground.BrightCyan +
	"Choice $([int]$choice.Index + 1): " +
	(Format-ChatCompletionResponseMessage $choice.Message)
}

function Format-CreateChatCompletionResponse {
	param(
		[OpenAI.CreateChatCompletionResponse]$response
	)
	if ($response.Choices.Count -eq 1) {
		Format-ChatCompletionResponseMessage $response.Choices[0].Message
	} else {
		$Response.Choices
	}
}