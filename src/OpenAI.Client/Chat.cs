
using System.Collections.ObjectModel;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.Json.Serialization;
using OpenAI.Extensions;

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

public class CreateChatCompletionChunkedResponse
{
	[JsonPropertyName("id")]
	[JsonIgnore(Condition = JsonIgnoreCondition.Never)]
	[System.ComponentModel.DataAnnotations.Required(AllowEmptyStrings = true)]
	public string Id { get; set; } = default!;

	[JsonPropertyName("object")]
	[JsonIgnore(Condition = JsonIgnoreCondition.Never)]
	[System.ComponentModel.DataAnnotations.Required(AllowEmptyStrings = true)]
	public string Object { get; set; } = default!;

	[JsonPropertyName("created")]
	[JsonIgnore(Condition = JsonIgnoreCondition.Never)]
	public int Created { get; set; } = default!;

	[JsonPropertyName("model")]
	[JsonIgnore(Condition = JsonIgnoreCondition.Never)]
	[System.ComponentModel.DataAnnotations.Required(AllowEmptyStrings = true)]
	public string Model { get; set; } = default!;

	[JsonPropertyName("choices")]
	[JsonIgnore(Condition = JsonIgnoreCondition.Never)]
	[System.ComponentModel.DataAnnotations.Required]
	public ICollection<DeltaChoice> Choices { get; set; }
}

public class DeltaChoice
{
	[JsonPropertyName("index")]
	[JsonIgnore(Condition = JsonIgnoreCondition.Never)]
	[System.ComponentModel.DataAnnotations.Required(AllowEmptyStrings = true)]
	public int? Index { get; set; }

	public ChatCompletionResponseMessage? Message { get; set; }

	[JsonPropertyName("finish_reason")]

	[JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)]
	public string? Finish_reason { get; set; }

	[JsonPropertyName("delta")]
	[JsonIgnore(Condition = JsonIgnoreCondition.Never)]
	public DeltaContent? Delta { get; set; }
}

public class DeltaContent
{
	[JsonPropertyName("role")]
	[JsonConverter(typeof(JsonStringEnumConverter))]
	[JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
	public ChatCompletionResponseMessageRole? Role { get; set; }

	[JsonPropertyName("content")]
	[JsonIgnore(Condition = JsonIgnoreCondition.Never)]
	[System.ComponentModel.DataAnnotations.Required(AllowEmptyStrings = true)]
	public string? Content { get; set; }
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

public partial class Client
{
	public IEnumerable<CreateChatCompletionChunkedResponse> CreateChatCompletionAsStream(CreateChatCompletionRequest request, CancellationToken cancellationToken = default)
	{
		return CreateChatCompletionAsStreamAsync(request, cancellationToken).ToBlockingEnumerable(cancellationToken);
	}

	public async IAsyncEnumerable<CreateChatCompletionChunkedResponse> CreateChatCompletionAsStreamAsync(CreateChatCompletionRequest request, [EnumeratorCancellation] CancellationToken cancellationToken = default)
	{
		// Enable streaming if it is not already enabled
		request.Stream = true;

		var urlBuilder = new System.Text.StringBuilder();
		urlBuilder.Append(BaseUrl != null ? BaseUrl.TrimEnd('/') : "").Append("/chat/completions");

		using var response = await _httpClient.PostAsync(urlBuilder.ToString(), request, _settings.Value, cancellationToken);

		await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
		using var reader = new StreamReader(stream);

		// Continuously read the stream until the end of it
		while (!reader.EndOfStream)
		{
			cancellationToken.ThrowIfCancellationRequested();

			var line = await reader.ReadLineAsync(cancellationToken);
			// Skip empty lines
			if (string.IsNullOrEmpty(line))
			{
				continue;
			}

			line = line.RemoveIfStartWith("data: ");

			// Exit the loop if the stream is done
			if (line.StartsWith("[DONE]"))
			{
				break;
			}

			CreateChatCompletionChunkedResponse? block;
			try
			{
				// When the response is good, each line is a serializable
				block = JsonSerializer.Deserialize<CreateChatCompletionChunkedResponse>(line);
			}
			catch
			{
				// When the API returns an error, it does not come back as a block, it returns a single character of text ("{").
				// In this instance, read through the rest of the response, which should be a complete object to parse.
				line += await reader.ReadToEndAsync(cancellationToken);
				block = JsonSerializer.Deserialize<CreateChatCompletionChunkedResponse>(line);
				throw;
			}

			if (block is not null)
			{
				yield return block;
			}
		}
	}
}