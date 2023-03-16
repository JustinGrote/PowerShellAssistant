# PowerShell Assistant

This module provides support for the OpenAI API and tools to leverage it including a chat client and PSReadline completer.

Requires Powershell 7.3 due to some .NET 7 feature usage.

## Code Generation

This module's core engine is an NSwag-generated C# client from the OpenAI OpenAPI specification. This should make it so that as new functions and models are released, they can be taken advantage of by regenerating the client.

## User Interface

The `Get-Chat` (aka `chat`) and `Get-Code` (aka `code`) are meant for interactive scenarios. `chat` can be used as a standalone interactive tool which will copy any recommended code discovered to your clipboard automatically. `code` is meant to provide suggestions based on existing code and context, and meant in the future to integrate as a suggestion provider into tools such as PSReadline.

`Get-AIChat` is the underlying engine that powers `Get-Chat` and can be used for more programmatic noninteractive scenarios.

## Formatting

This module strives so that all UI "output" is done with custom format files rather than write-host or raw strings. This ensures that you still have access to the underlying "object" underneath without requiring a `-Raw` or similar parameter parameter

## Alternatives

Check out Doug Finke's excellent [PowerShellAI](https://github.com/dfinke/PowerShellAI) module for a pure-PowerShell implementation of OpenAI.
