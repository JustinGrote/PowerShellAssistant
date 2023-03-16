// Taken with love from: https://github.com/betalgo/openai/blob/master/OpenAI.SDK/Extensions/StringExtensions.cs

namespace OpenAI.Extensions;

/// <summary>
///     Extension methods for string manipulation
/// </summary>
public static class StringExtensions
{
	/// <summary>
	///     Remove the search string from the begging of string if exist
	/// </summary>
	/// <param name="text"></param>
	/// <param name="search"></param>
	/// <returns></returns>
	public static string RemoveIfStartWith(this string text, string search)
	{
		var pos = text.IndexOf(search, StringComparison.Ordinal);
		return pos != 0 ? text : text[search.Length..];
	}
}