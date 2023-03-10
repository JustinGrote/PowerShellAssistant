@{
	'OpenAI.Engine'                        = 'Id', 'Ready'
	'OpenAI.Model'                         = 'Id', 'Created', 'Owned_By'
	'OpenAI.CreateCompletionResponse'      = 'Model', 'Created', 'Choices', 'Usage'
	'OpenAI.ChatCompletionResponseMessage' = { & (Get-Module PowerShellAssistant) { Format-ChatCompletionResponseMessage $args[0] } $PSItem }
	'OpenAI.CreateChatCompletionResponse'  = { & (Get-Module PowerShellAssistant) { Format-CreateChatCompletionResponse $args[0] } $PSItem }
	'OpenAI.Choices2'                      = { & (Get-Module PowerShellAssistant) { Format-Choices2 $args[0] } $PSItem }
}