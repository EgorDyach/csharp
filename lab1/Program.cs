using lab1.Models;
using lab1.Services;

namespace lab1;

class Program
{
    static void Main(string[] args)
    {
        var serializer = new PersonSerializer();
        
        var person = new Person("Иван", "Филиппов", 18, "ivan.filippov@mail.ru", "123123123");
        
        Console.WriteLine($"Полное имя: {person.FullName}");
        Console.WriteLine($"Совершеннолетний: {person.IsAdult}");
        
        var json = serializer.SerializeToJson(person);
        Console.WriteLine($"Сериализованный JSON:\n{json}");
        
        var filePath = "person.json";
        serializer.SaveToFile(person, filePath);
        Console.WriteLine($"Сохранено в {filePath}");
        
        var loadedPerson = serializer.LoadFromFile(filePath);
        Console.WriteLine($"Загружено: {loadedPerson.FullName}");
    }
}

