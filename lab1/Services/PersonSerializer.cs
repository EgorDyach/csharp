using System.Text;
using System.Text.Json;
using lab1.Models;

namespace lab1.Services;

public class PersonSerializer
{
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public string SerializeToJson(Person person)
    {
        if (person == null)
            throw new ArgumentNullException(nameof(person));

        return JsonSerializer.Serialize(person, Options);
    }

    public Person? DeserializeFromJson(string json)
    {
        if (string.IsNullOrWhiteSpace(json))
            throw new ArgumentException("json строка не может быть пустой", nameof(json));

        try
        {
            return JsonSerializer.Deserialize<Person>(json, Options);
        }
        catch (JsonException ex)
        {
            LogError($"ошибка десериализации json: {ex.Message}");
            throw;
        }
    }

    public void SaveToFile(Person person, string filePath)
    {
        if (person == null)
            throw new ArgumentNullException(nameof(person));
        if (string.IsNullOrWhiteSpace(filePath))
            throw new ArgumentException("путь к файлу не может быть пустым", nameof(filePath));

        try
        {
            var json = SerializeToJson(person);
            File.WriteAllText(filePath, json, Encoding.UTF8);
        }
        catch (Exception ex)
        {
            LogError($"ошибка сохранения в файл: {ex.Message}");
            throw;
        }
    }

    public Person LoadFromFile(string filePath)
    {
        if (string.IsNullOrWhiteSpace(filePath))
            throw new ArgumentException("путь к файлу не может быть пустым", nameof(filePath));
        if (!File.Exists(filePath))
            throw new FileNotFoundException("файл не найден", filePath);

        try
        {
            var json = File.ReadAllText(filePath, Encoding.UTF8);
            var person = DeserializeFromJson(json);
            if (person == null)
                throw new InvalidOperationException("объект равен null");
            return person;
        }
        catch (Exception ex)
        {
            LogError($"ошибка загрузки из файла: {ex.Message}");
            throw;
        }
    }

    public async Task SaveToFileAsync(Person person, string filePath)
    {
        if (person == null)
            throw new ArgumentNullException(nameof(person));
        if (string.IsNullOrWhiteSpace(filePath))
            throw new ArgumentException("путь к файлу не может быть пустым", nameof(filePath));

        try
        {
            var json = SerializeToJson(person);
            await File.WriteAllTextAsync(filePath, json, Encoding.UTF8);
        }
        catch (Exception ex)
        {
            LogError($"ошибка асинхронного сохранения в файл: {ex.Message}");
            throw;
        }
    }

    public async Task<Person> LoadFromFileAsync(string filePath)
    {
        if (string.IsNullOrWhiteSpace(filePath))
            throw new ArgumentException("путь к файлу не может быть пустым", nameof(filePath));
        if (!File.Exists(filePath))
            throw new FileNotFoundException("файл не найден", filePath);

        try
        {
            var json = await File.ReadAllTextAsync(filePath, Encoding.UTF8);
            var person = DeserializeFromJson(json);
            if (person == null)
                throw new InvalidOperationException("десериализованный объект равен null");
            return person;
        }
        catch (Exception ex)
        {
            LogError($"ошибка асинхронной загрузки из файла: {ex.Message}");
            throw;
        }
    }

    public void SaveListToFile(List<Person> people, string filePath)
    {
        if (people == null)
            throw new ArgumentNullException(nameof(people));
        if (string.IsNullOrWhiteSpace(filePath))
            throw new ArgumentException("путь к файлу не может быть пустым", nameof(filePath));

        try
        {
            var json = JsonSerializer.Serialize(people, Options);
            File.WriteAllText(filePath, json, Encoding.UTF8);
        }
        catch (Exception ex)
        {
            LogError($"ошибка сохранения списка в файл: {ex.Message}");
            throw;
        }
    }

    public List<Person> LoadListFromFile(string filePath)
    {
        if (string.IsNullOrWhiteSpace(filePath))
            throw new ArgumentException("путь к файлу не может быть пустым", nameof(filePath));
        if (!File.Exists(filePath))
            throw new FileNotFoundException("файл не найден", filePath);

        try
        {
            var json = File.ReadAllText(filePath, Encoding.UTF8);
            var people = JsonSerializer.Deserialize<List<Person>>(json, Options);
            return people ?? new List<Person>();
        }
        catch (Exception ex)
        {
            LogError($"ошибка загрузки списка из файла: {ex.Message}");
            throw;
        }
    }

    private static void LogError(string message)
    {
        try
        {
            var logPath = "errors.log";
            var logMessage = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {message}{Environment.NewLine}";
            File.AppendAllText(logPath, logMessage, Encoding.UTF8);
        }
        catch
        {
        }
    }
}

