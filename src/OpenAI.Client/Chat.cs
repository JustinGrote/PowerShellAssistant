using System.Runtime.CompilerServices;

namespace OpenAI;

/// <summary>
/// Combines a chat request and response into a single object to provide context for conversations.
/// </summary>
public record ChatConversation
{
	public CreateChatCompletionRequest Request { get; set; }
	public CreateChatCompletionResponse Response { get; set; }

	public ChatConversation()
	{
		Request = new();
		Response = new();
	}
}

/// <summary>
/// Unifying interface for the various chat messages. Actual interface cannot be used due to enums
/// </summary>
public record ChatMessage
{
	public ChatMessageRole Role;
	public string Content = string.Empty;

	// TODO: There must be a more generic way to implement this than explicit constructors
	public ChatMessage(ChatCompletionResponseMessage message)
	{
		Role = Enum.Parse<ChatMessageRole>(message.Role.ToString());
		Content = message.Content;
	}

	public ChatMessage(ChatCompletionRequestMessage message)
	{
		Role = Enum.Parse<ChatMessageRole>(message.Role.ToString());
		Content = message.Content;
	}
}

public enum ChatMessageRole
{
	[System.Runtime.Serialization.EnumMember(Value = "system")]
	System = 0,

	[System.Runtime.Serialization.EnumMember(Value = "user")]
	User = 1,

	[System.Runtime.Serialization.EnumMember(Value = "assistant")]
	Assistant = 2,
}