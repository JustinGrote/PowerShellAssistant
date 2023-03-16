using namespace OpenAI
using namespace System.Net.Http
using namespace System.Net.Http.Headers
using namespace System.Collections.Generic
using namespace System.Management.Automation

$ErrorActionPreference = 'Stop'
#TODO: This should be better
$debugBinPath = Join-Path $PSScriptRoot '/bin/Debug/net7.0'
if (Test-Path $debugBinPath) {
	Write-Warning "Debug build detected. Using assemblies at $debugBinPath"
	Add-Type -Path $debugBinPath/*.dll
} else {
	Add-Type -Path $PSScriptRoot/*.dll
}

#These are the cheapest models for testing, opt into more powerful models
$SCRIPT:aiDefaultModel = 'ada'
$SCRIPT:aiDefaultChatModel = 'gpt-3.5-turbo'
$SCRIPT:aiDefaultCodeModel = 'code-davinci-002'


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

	$client = New-AIClient @newAIClientParams -APIKey $APIKey -GithubCopilot:$GitHubCopilot

	if ($NoDefault) {
		$PassThru = $true
	} else {
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

function Get-AICode {
	<#
	.SYNOPSIS
	Utilizes the Codex models to fetch a code completion given a prompt.
	.LINK
	https://platform.openai.com/docs/guides/code/introduction
	#>
	[OutputType([OpenAI.CreateCompletionResponse])]
	[CmdletBinding()]
	param(
		[string[]]$Prompt,
		#The name of the model to use.
		$Language = 'PowerShell 7',
		[ValidateSet([AvailableModels])][String]$Model = $SCRIPT:aiDefaultCodeModel,
		[ValidateNotNullOrEmpty()][OpenAI.Client]$Client = $SCRIPT:aiClient,
		[ValidateNotNullOrEmpty()][uint]$MaxTokens = 1000,
		[ValidateNotNullOrEmpty()][uint]$Temperature = 0
	)
	if (-not $Client) {
		Assert-Connected
		$Client = $SCRIPT:aiClient
	}

	#Add a language specifier to the prompt
	$Prompt.Insert(0, "#$Language")

	Get-AICompletion -Prompt $Prompt -Model $Model -MaxTokens $MaxTokens -Temperature $Temperature
}

function Get-AIChat {
	[OutputType([OpenAI.ChatConversation])]
	[CmdletBinding(DefaultParameterSetName = 'Prompt')]
	param(
		#Include one or more prompts to start the conversation
		[Parameter(Mandatory, Position = 0, ValueFromPipeline, ParameterSetName = 'Prompt')]
		[Parameter(ParameterSetName = 'ChatSession')]
		[OpenAI.ChatCompletionRequestMessage[]]$Prompt,

		#Supply a previous chat session to add new responses to it
		[Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ChatSession')]
		[Parameter(ParameterSetName = 'Prompt')]
		[OpenAI.ChatConversation]$ChatSession,

		#The name of the model to use.
		[ValidateSet([AvailableModels])]
		[String]$Model = $SCRIPT:aiDefaultChatModel,

		[ValidateNotNullOrEmpty()]
		[OpenAI.Client]$Client = $SCRIPT:aiClient,

		[ValidateNotNullOrEmpty()]
		[uint]$MaxTokens = 1000,

		[ValidateNotNullOrEmpty()]
		[uint]$Temperature = 0,

		#Stream the response. You will lose syntax highlighting and usage info.
		[switch]$Stream
	)
	if (-not $Client) {
		Assert-Connected
		$Client = $SCRIPT:aiClient
	}

	$ChatSession ??= [ChatConversation]@{
		Request = @{
			Messages    = [List[ChatCompletionRequestMessage]]@()
			Stream      = $false
			Model       = $Model
			Max_tokens  = $MaxTokens
			Temperature = $Temperature
		}
	}

	#Append any response to the initial request. This is the continuation of a chat.
	$responseChoices = $ChatSession.Response.Choices
	$requestMessages = $ChatSession.Request.Messages
	if ($responseChoices.Count -gt 0) {
		if ($responseChoices.count -gt 1) {
			Write-Error 'The previous chat response contained more than one choice. Continuing a conversation with multiple choices is not supported.' -Category 'NotImplemented'
			return
		}
		$requestMessages.Add($responseChoices[0].Message)
	}

	foreach ($PromptItem in $Prompt) {
		$requestMessages.Add(
			$PromptItem
		)
	}

	if ($Stream) {
		$Client.CreateChatCompletionAsStream($ChatSession.Request)
		| ForEach-Object {
			Write-Host -NoNewline $PSItem.Choices[0].Delta.Content
		}
		Write-Host
		return
	}

	$chatResponse = $Client.CreateChatCompletion($ChatSession.Request)
	$chatSession.Response = $chatResponse

	$price = Get-UsagePrice -Model $chatResponse.Model -Total $chatResponse.Usage.Total_tokens

	Write-Verbose "Chat usage - $($chatResponse.Usage) $($price ? "$price " : $null)for Id $($chatResponse.Id)"
	return $chatSession

	#Stream the response
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

function Update-GitHubCopilotToken {
	<#
	.SYNOPSIS
	Fetches the latest token for GitHub Copilot
	#>
	param(
		[ValidateNotNullOrEmpty()]
		$GitHubToken = $SCRIPT:GHCopilotToken
	)
	$ErrorActionPreference = 'Stop'
	$response = Invoke-RestMethod 'https://api.github.com/copilot_internal/v2/token' -Headers @{
		Authorization = "token $($GitHubToken.trim())"
	}
	return $response.token
}

function Get-Chat {
	<#
	.SYNOPSIS
	Provides an interactive assistant for PowerShell. Mostly a frontend to Get-AIChat
	#>
	[CmdletBinding()]
	param(
		#Provide a chat prompt to initiate the conversation
		[string[]]$chatPrompt,

		#If you just want the result and don't want to be prompted for further replies, specify this
		[Switch]$NoReply,

		#By default, the latest code recommendation is copied to your clipboard, specify this to disable the behavior
		[switch]$NoClipboard,

		[ValidateNotNullOrEmpty()]
		#Specify a prompt that guides Chat how to behave. By default, it is told to prefer PowerShell as a language.
		[string]$SystemPrompt = 'PowerShell syntax and be brief',

		#Maximum tokens to generate. Defaults to 500 to minimize accidental API billing
		[ValidateNotNullOrEmpty()]
		[uint]$MaxTokens = 500,

		[ValidateSet([AvailableModels])]
		[string]$Model

		#TODO: Figure out how to autocomplete this
	)
	begin {
		$ErrorActionPreference = 'Stop'
		Assert-Connected
		[List[ChatCompletionRequestMessage]]$chatHistory = @(
			[ChatCompletionRequestMessage]@{
				Role    = [ChatCompletionRequestMessageRole]::System
				Content = $SystemPrompt
			}
		)
	}
	process {
		do {
			$chatPrompt ??= Read-Host -Prompt 'You'
			foreach ($promptItem in $chatPrompt) {
				$chatHistory.Add(
					([ChatCompletionRequestMessage]$promptItem)
				)
			}

			$chatParams = @{
				Prompt    = $chatHistory
				MaxTokens = $MaxTokens
			}
			if ($Model) { $chatParams.Model = $Model }

			$result = Get-AIChat @chatParams

			foreach ($message in $result.Choices.Message) {
				$chatHistory.Add([ChatCompletionRequestMessage]$message)
			}

			Write-Output $result.Response

			if (-not $NoClipboard) {
				$result.Response.Choices[0].Message.Content
				| Convert-ChatCodeToClipboard
				| Out-Null
			}

			#TODO: Move this into the formatter
			# switch ($aiResponse.FinishReason) {
			# 	'stop' {} #This is the normal response
			# 	'length' {
			# 		Write-Warning "$MaxTokens tokens reached. Consider increasing the value of -MaxTokens for longer responses."
			# 	}
			# 	$null {
			# 		Write-Debug 'Null FinishReason received. This seems to occur on occasion and may or may not be a bug.'
			# 	}
			# 	default {
			# 		Write-Warning "Chat response finished abruply due to: $($aiResponse.FinishReason)"
			# 	}
			# }

			$chatPrompt = $null
			if (-not $NoReply) {
				Write-Host -Fore Cyan '<Ctrl-C to exit>'
			}
		} while (
			-not $NoReply
		)
	}
}

filter Convert-ChatCodeToClipboard {
	<#
	.SYNOPSIS
	Given a string, take the last occurance of text surrounded by a fenced code block, and copy it to the clipboard.
	It will also pass through the string for further filtering
	#>
	$fencedCodeBlockRegex = '(?s)```[\r|\n|powershell]+(.+?)```'
	$matchResult = $PSItem -match $fencedCodeBlockRegex
	$savedMatches = $matches
	$cbMatch = $savedMatches.($savedMatches.Keys | Sort-Object | Select-Object -Last 1)
	if (-not $matchResult) {
		Write-Debug 'No code block detected, skipping this step'
		return $PSItem
	}

	Write-Verbose "Copying last suggested code block to clipboard:`n$cbMatch"
	Set-Clipboard -Value $cbMatch

	return $PSItem
}

class AvailableModels : IValidateSetValuesGenerator {
	[String[]] GetValidValues() {
		trap { Write-Host ''; Write-Host -NoNewline -ForegroundColor Red "Validation Error: $PSItem" }
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

filter Format-ChatMessage {
	param(
		[Parameter(ValueFromPipeline)]$message,
		#Notes that the content should be streamed rather than returned line by line
		[switch]$Stream
	)

	$role = $message.Role
	$content = $message.Content

	$roleColor = switch ($role) {
		'System' { 'DarkYellow' }
		'Assistant' { 'Green' }
		'User' { 'DarkCyan' }
		default { 'DarkGray' }
	}
	$formattedMessage = $content.Trim() | Format-ChatCode
	if (-not $Stream) {
		return "$($PSStyle.Foreground.$roleColor)$role`:$($PSStyle.Reset) $($PSStyle.ForeGround.BrightBlack)$formattedMessage"
	}

	if ($role) {
		[console]::Write('a')
		# [Console]::Write("$($PSStyle.Foreground.$roleColor)$role`:$($PSStyle.Reset) ")
	} elseif ($content) {
		[console]::Write('b')
		# [Console]::Write("$($PSStyle.ForeGround.BrightBlack)$content$($PSStyle.Reset)")
	}
}

function Format-CreateChatCompletionChunkedResponse {
	param(
		[Parameter(ValueFromPipeline)][CreateChatCompletionChunkedResponse]$response
	)
	Format-ChatMessage -Stream $response.Choices[0].Delta
}

function Format-Choices2 {
	param(
		[Choices2]$choice
	)
	$PSStyle.Foreground.BrightCyan +
	"Choice $([int]$choice.Index + 1): " +
	(Format-ChatMessage $choice.Message)
}

filter Format-CreateChatCompletionRequest {
	param(
		[Parameter(ValueFromPipeline)][CreateChatCompletionRequest]$request
	)
	$request.messages | Format-ChatMessage
}
filter Format-CreateChatCompletionResponse {
	param(
		[Parameter(ValueFromPipeline)][CreateChatCompletionResponse]$response
	)
	if ($response.Choices.Count -eq 1) {
		Format-ChatMessage $response.Choices[0].Message
	} else {
		$Response.Choices
	}
}

function Format-ChatConversation {
	param(
		[ChatConversation]$conversation
	)
	$messages = @()

	$messages += $conversation.Request | Format-CreateChatCompletionRequest
	$messages += $conversation.Response | Format-CreateChatCompletionResponse
	return $messages -join ($PSStyle.Reset + [Environment]::NewLine)
}

function Get-UsagePrice {
	param(
		[string]$Model,
		[int]$Total
	)

	#Taken from: https://openai.com/pricing
	$pricePerToken = @{
		'code'          = 0
		'gpt-3.5-turbo' = .002 / 1000
		'ada'           = .0004 / 1000
		'babbage'       = .0005 / 1000
		'curie'         = .002 / 1000
		'davinci'       = .002 / 1000
	}

	foreach ($priceItem in $pricePerToken.GetEnumerator()) {
		if ($Model.Contains($priceItem.key)) {
			#Will return the first match
			$totalPrice = $total * $priceItem.Value

			#Formats as currency ($3.2629) and strips trailing zeroes
			return $totalPrice.ToString('C15').TrimEnd('0')
		}
	}

	#Return an empty string if no pricing engine found.
	return [string]::Empty

}

