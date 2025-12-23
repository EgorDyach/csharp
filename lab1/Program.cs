using lab1.Models;
using lab1.Services;

namespace lab1;

class Program
{
    static void Main(string[] args)
    {
        var serializer = new PersonSerializer();
        
        var person = new Person("Иван", "Филиппов", 18, "ivan.filippov@mail.ru", "123123123", "id001", new DateTime(2006, 5, 15), "+79001234567");
        
        Console.WriteLine($"Имя: {person.FirstName} {person.LastName}");
        Console.WriteLine($"ID: {person.Id}");
        Console.WriteLine($"Дата рождения: {(person.BirthDate.HasValue ? person.BirthDate.Value.ToString("yyyy-MM-dd") : "не указана")}");
        Console.WriteLine($"Телефон: {person.PhoneNumber}");
        
        var json = serializer.SerializeToJson(person);
        Console.WriteLine($"\nСериализованный JSON:\n{json}");
        
        var filePath = "person.json";
        serializer.SaveToFile(person, filePath);
        Console.WriteLine($"\nСохранено в {filePath}");
        
        var loadedPerson = serializer.LoadFromFile(filePath);
        Console.WriteLine($"Загружено: {loadedPerson.FirstName} {loadedPerson.LastName}");
    }
}

