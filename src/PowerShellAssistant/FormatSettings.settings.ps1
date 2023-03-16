@{
	'OpenAI.Engine'                        = 'Id', 'Ready'
	'OpenAI.Model'                         = 'Id', 'Created', 'Owned_By'
	'OpenAI.CreateCompletionResponse'      = 'Model', 'Created', 'Choices', 'Usage'
	'OpenAI.ChatCompletionRequestMessage'  = { & (Get-Module PowerShellAssistant) { Format-ChatMessage $args[0] } $PSItem }
	'OpenAI.ChatCompletionResponseMessage' = { & (Get-Module PowerShellAssistant) { Format-ChatMessage $args[0] } $PSItem }
	'OpenAI.CreateChatCompletionRequest'   = { & (Get-Module PowerShellAssistant) { Format-CreateChatCompletionRequest $args[0] } $PSItem }
	'OpenAI.CreateChatCompletionResponse'  = { & (Get-Module PowerShellAssistant) { Format-CreateChatCompletionResponse $args[0] } $PSItem }
	'OpenAI.Choices2'                      = { & (Get-Module PowerShellAssistant) { Format-Choices2 $args[0] } $PSItem }
	'OpenAI.ChatConversation'              = { & (Get-Module PowerShellAssistant) { Format-ChatConversation $args[0] } $PSItem }
	'OpenAI.CreateChatCompletionChunkedResponse' = { & (Get-Module PowerShellAssistant) { Format-CreateChatCompletionChunkedResponse $args[0] } $PSItem }
}