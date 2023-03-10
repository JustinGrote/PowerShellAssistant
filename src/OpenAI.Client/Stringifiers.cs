namespace OpenAI;

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

public partial class ChatCompletionRequestMessage
{
	public override string ToString()
	{
		return $"{Role}: {Content}";
	}
}

public partial class Choices2
{
	public override string ToString()
	{
		return Index.HasValue
			? $"Choice {Index + 1} - {Message?.Role}: {Message?.Content}"
			: $"{Message?.Role}: {Message?.Content}";
	}
}