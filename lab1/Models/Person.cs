using System.Text.Json.Serialization;

namespace lab1.Models;

public class Person
{
    [JsonPropertyName("firstName")]
    public string FirstName { get; set; } = string.Empty;

    [JsonPropertyName("lastName")]
    public string LastName { get; set; } = string.Empty;

    [JsonPropertyName("age")]
    public int Age { get; set; }

    [JsonPropertyName("email")]
    public string Email { get; set; } = string.Empty;

    [JsonIgnore]
    public string Password { get; set; } = string.Empty;

    [JsonIgnore]
    public string FullName => $"{FirstName} {LastName}";

    [JsonIgnore]
    public bool IsAdult => Age >= 18;

    public Person()
    {
    }

    public Person(string firstName, string lastName, int age, string email, string password)
    {
        if (string.IsNullOrWhiteSpace(firstName))
            throw new ArgumentException("имя не может быть пустым", nameof(firstName));
        if (string.IsNullOrWhiteSpace(lastName))
            throw new ArgumentException("фамилия не может быть пустой", nameof(lastName));
        if (age < 0)
            throw new ArgumentException("возраст не может быть отрицательным", nameof(age));
        if (!IsValidEmail(email))
            throw new ArgumentException("некорректный формат email", nameof(email));

        FirstName = firstName;
        LastName = lastName;
        Age = age;
        Email = email;
        Password = password;
    }

    private static bool IsValidEmail(string email)
    {
        return !string.IsNullOrWhiteSpace(email) && email.Contains('@');
    }
}

