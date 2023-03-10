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