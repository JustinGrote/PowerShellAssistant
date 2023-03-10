namespace OpenAI;

using System.Reflection;
using System.Runtime.Serialization;
using System.Text.Json;
using System.Text.Json.Serialization;

/// <summary>
/// This custom enum converter supports custom name serialization using either the JsonPropertyName or EnumMember attributes. Required because System.Text.JSON doesn't support custom enum names.
/// </summary>
public class JsonStringEnumConverter : JsonConverterFactory
{
	public override bool CanConvert(Type typeToConvert)
	{
		return typeToConvert.IsEnum;
	}

	public override JsonConverter? CreateConverter(Type typeToConvert, JsonSerializerOptions options)
	{
		var type = typeof(JsonStringEnumConverter<>).MakeGenericType(typeToConvert);
		return (JsonConverter)Activator.CreateInstance(type)!;
	}
}

public class JsonStringEnumConverter<TEnum> : JsonConverter<TEnum> where TEnum : struct, Enum
{
	private readonly Dictionary<TEnum, string> _enumToString = new();
	private readonly Dictionary<string, TEnum> _stringToEnum = new();
	private readonly Dictionary<int, TEnum> _numberToEnum = new();

	public JsonStringEnumConverter()
	{
		var type = typeof(TEnum);
		foreach (var value in Enum.GetValues<TEnum>())
		{
			var enumMember = type.GetMember(value.ToString())[0];
			var attr = enumMember.GetCustomAttributes<JsonPropertyNameAttribute>().FirstOrDefault();

			var serializationAttr = enumMember.GetCustomAttributes<EnumMemberAttribute>().FirstOrDefault();

			var num = Convert.ToInt32(type.GetField("value__")?.GetValue(value));
			if (attr?.Name != null)
			{
				_enumToString.Add(value, attr.Name);
				_stringToEnum.Add(attr.Name, value);
				_numberToEnum.Add(num, value);
			}
			else if (serializationAttr?.Value != null)
			{
				_enumToString.Add(value, serializationAttr.Value);
				_stringToEnum.Add(serializationAttr.Value, value);
				_numberToEnum.Add(num, value);
			}
			else
			{
				_enumToString.Add(value, value.ToString());
				_stringToEnum.Add(value.ToString(), value);
				_numberToEnum.Add(num, value);
			}
		}
	}

	public override TEnum Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
	{
		var type = reader.TokenType;
		if (type == JsonTokenType.String)
		{
			var stringValue = reader.GetString();

			if (stringValue != null && _stringToEnum.TryGetValue(stringValue, out var enumValue))
			{
				return enumValue;
			}
		}
		else if (type == JsonTokenType.Number)
		{
			var numValue = reader.GetInt32();
			_numberToEnum.TryGetValue(numValue, out var enumValue);
			return enumValue;
		}

		return default;
	}

	public override void Write(Utf8JsonWriter writer, TEnum value, JsonSerializerOptions options)
	{
		writer.WriteStringValue(_enumToString[value]);
	}
}