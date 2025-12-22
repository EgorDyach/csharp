using System.Text.Json.Serialization;

namespace lab1.Models;

public class Person
{
    public string FirstName { get; set; } = string.Empty;

    public string LastName { get; set; } = string.Empty;

    public int Age { get; set; }

    private string _email = string.Empty;
    public string Email
    {
        get => _email;
        set
        {
            if (!IsValidEmail(value))
                throw new ArgumentException("некорректный формат email", nameof(value));
            _email = value;
        }
    }

    [JsonIgnore]
    public string Password { get; set; } = string.Empty;

    [JsonPropertyName("personId")]
    public string Id { get; set; } = string.Empty;

    [JsonInclude]
    private DateTime _birthDate;

    public DateTime BirthDate
    {
        get => _birthDate;
        set => _birthDate = value;
    }

    [JsonPropertyName("phone")]
    public string PhoneNumber { get; set; } = string.Empty;

    public Person()
    {
    }

    public Person(string firstName, string lastName, int age, string email, string password, string id = "", DateTime? birthDate = null, string phoneNumber = "")
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
        Id = id;
        _birthDate = birthDate ?? DateTime.MinValue;
        PhoneNumber = phoneNumber;
    }

    private static bool IsValidEmail(string email)
    {
        return !string.IsNullOrWhiteSpace(email) && email.Contains('@');
    }
}

