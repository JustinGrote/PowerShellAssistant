using namespace OpenAI.GPT3
using namespace OpenAI.GPT3.ObjectModels
using namespace OpenAI.GPT3.ObjectModels.RequestModels
using namespace OpenAI.GPT3.ObjectModels.ResponseModels
using namespace OpenAI.GPT3.Managers
using namespace System.Collections.Generic
function Connect-Assistant {
	param(
		# Provide your API Key as the password, and optionally your organization ID as the username
		[ValidateNotNullOrEmpty()]
		[string]$APIKey = $env:OPENAI_API_KEY,

		[Models]$Model,

		#Reset if a client already exists
		[Switch]$Force
	)
	$ErrorActionPreference = 'Stop'

	if ($SCRIPT:client -and -not $Force) {
		Write-Warning 'Assistant is already connected. Please use -Force to reset the client.'
		return
	}
	$config = [OpenAIOptions]@{
		ApiKey = $APIKey
	}

	$SCRIPT:client = [OpenAIService]::new($config)

	if ($Model) {
		$client.SetDefaultModelId($Model)
	}
}

function Assert-Connected {
	if (-not $SCRIPT:client) { Connect-Assistant }
}

function Get-Chat {
	param(
		#Provide a chat prompt to initiate the conversation
		[string[]]$chatPrompt,

		[ValidateNotNullOrEmpty()]
		#Specify a prompt that guides Chat how to behave. By default, it is told to prefer PowerShell as a language.
		[string]$SystemPrompt = 'Use PowerShell syntax and responses should be as brief as possible',

		#Maximum tokens to generate. Defaults to 500 to minimize accidental API billing
		[ValidateNotNullOrEmpty()]
		[uint]$MaxTokens = 500,

		[ValidateNotNullOrEmpty()]
		[string]$Model = [Models]::ChatGpt3_5Turbo
		#TODO: Figure out how to autocomplete this
	)
	begin {
		$ErrorActionPreference = 'Stop'
		Assert-Connected
		[List[ChatMessage]]$chatHistory = @(
			[ChatMessage]::FromSystem($SystemPrompt)
		)
	}
	process {
		while ($true) {
			$chatPrompt ??= Read-Host -Prompt 'You'
			$chatHistory.Add(
				[ChatMessage]::FromUser($chatPrompt)
			)
			$request = [ChatCompletionCreateRequest]@{
				Messages  = $chatHistory
				MaxTokens = $MaxTokens
				Model     = $Model
			}

			#TODO: Loop this and make it cancellable
			[ResponseModels.ChatCompletionCreateResponse]$response = $client.
			ChatCompletion.
			CreateCompletion($request).
			GetAwaiter().
			GetResult()

			if (-not $response.Successful) {
				$errCode = $response.Error.Code ?? 'UNKNOWN'
				$errMsg = $response.Error.Message ?? 'Unknown error'
				Write-Error "$errCode - $errMsg"
				return
			}

			$aiResponse = $response.Choices[0] ?? { throw new Exception('No response from AI. This is a probably a bug you should report.') }

			[string]$responseMessage = $aiResponse.Message.Content

			$chatHistory.Add(
				[ChatMessage]::FromAssistance($responseMessage)
			)
			Write-Host -Fore DarkGray $responseMessage

			#Handle various bugs that might occur
			if ($aiResponse.Message.Role -ne 'assistant') {
				Write-Warning 'Chat response was not from the assistant. This is a probably a bug you should report.'
			}
			if ($aiResponse.FinishReason -ne 'stop') {
				Write-Warning "Chat response finished abruply due to: $($aiResponse.FinishReason)"
			}
			$chatPrompt = $null
		}
	}
}
