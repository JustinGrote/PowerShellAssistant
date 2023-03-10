BeforeAll {
	$ManifestPath = Resolve-Path (Join-Path $PSScriptRoot '../src/PowerShellAssistant/PowerShellAssistant.psd1')
	Import-Module $ManifestPath
}
Describe 'Get-AIChat' {
	Context 'When called with no parameters' {
		It 'Should return a chat' -Pending {
			$chat = Get-AIChat 'Return only the word PESTER'
			$chat | Should -Be 'PESTER'
		}
	}
}