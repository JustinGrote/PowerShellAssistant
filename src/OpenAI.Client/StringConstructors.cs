namespace OpenAI;

public partial class ChatCompletionRequestMessage
{
	public ChatCompletionRequestMessage() { }

	public ChatCompletionRequestMessage(ChatCompletionResponseMessage responseMessage)
	{
		Content = responseMessage.Content;
		Role = Enum.Parse<ChatCompletionRequestMessageRole>(responseMessage.Role.ToString());
	}

	public ChatCompletionRequestMessage(string userMessage) : this(userMessage, ChatCompletionRequestMessageRole.User) { }

	public ChatCompletionRequestMessage(string userMessage, ChatCompletionRequestMessageRole role = ChatCompletionRequestMessageRole.User)
	{
		Role = role;
		Content = userMessage;
	}
}

public partial class Usage
{
	public static string ToUsageString(int total, int prompt, int? completion)
	{
		if (completion.HasValue)
			return $"Total: {total} (Prompt: {prompt}, Completion: {completion.Value})";
		else
			return $"Total: {total} (Prompt: {prompt})";
	}
	public override string ToString()
	{
		return ToUsageString(Total_tokens, Prompt_tokens, Completion_tokens);
	}
}
public partial class Usage2
{
	public override string ToString()
	{
		return Usage.ToUsageString(Total_tokens, Prompt_tokens, Completion_tokens);
	}
}
public partial class Usage3
{
	public override string ToString()
	{
		return Usage.ToUsageString(Total_tokens, Prompt_tokens, Completion_tokens);
	}
}
public partial class Usage4
{
	public override string ToString()
	{
		return Usage.ToUsageString(Total_tokens, Prompt_tokens, null);
	}
}