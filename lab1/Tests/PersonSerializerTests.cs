using lab1.Models;
using lab1.Services;
using Xunit;

namespace lab1.Tests;

public class PersonSerializerTests
{
    private readonly PersonSerializer _serializer = new();
    private readonly string _testFilePath = "test_person.json";
    private readonly string _testListFilePath = "test_people.json";

    [Fact]
    public void SerializeToJson_ShouldReturnValidJson()
    {
        var person = new Person("Анастасия", "Гордиенко", 18, "anastasia.gordienko@gmail.com", "123123123");
        var json = _serializer.SerializeToJson(person);
        
        Assert.NotNull(json);
        
        var deserialized = _serializer.DeserializeFromJson(json);
        Assert.NotNull(deserialized);
        Assert.Equal("Анастасия", deserialized.FirstName);
        Assert.Equal("Гордиенко", deserialized.LastName);
        Assert.DoesNotContain("123123123", json);
    }

    [Fact]
    public void DeserializeFromJson_ShouldReturnValidPerson()
    {
        var json = "{\"firstName\":\"Владислав\",\"lastName\":\"Ганьшин\",\"age\":17,\"email\":\"vladislav.ganshin@yandex.ru\"}";
        var person = _serializer.DeserializeFromJson(json);
        
        Assert.NotNull(person);
        Assert.Equal("Владислав", person.FirstName);
        Assert.Equal("Ганьшин", person.LastName);
        Assert.Equal(17, person.Age);
        Assert.Equal("vladislav.ganshin@yandex.ru", person.Email);
    }

    [Fact]
    public void SaveToFile_ShouldCreateFile()
    {
        var person = new Person("Дарья", "Горбунова", 17, "darya.gorbunova@mail.ru", "123123123");
        
        if (File.Exists(_testFilePath))
            File.Delete(_testFilePath);
        
        _serializer.SaveToFile(person, _testFilePath);
        
        Assert.True(File.Exists(_testFilePath));
        File.Delete(_testFilePath);
    }

    [Fact]
    public void LoadFromFile_ShouldReturnPerson()
    {
        var person = new Person("Кирилл", "Баранов", 18, "kirill.baranov@gmail.com", "123123123");
        _serializer.SaveToFile(person, _testFilePath);
        
        var loaded = _serializer.LoadFromFile(_testFilePath);
        
        Assert.Equal(person.FirstName, loaded.FirstName);
        Assert.Equal(person.LastName, loaded.LastName);
        Assert.Equal(person.Age, loaded.Age);
        Assert.Equal(person.Email, loaded.Email);
        
        File.Delete(_testFilePath);
    }

    [Fact]
    public async Task SaveToFileAsync_ShouldCreateFile()
    {
        var person = new Person("Ника", "Васильева", 17, "nika.vasilieva@yandex.ru", "123123123");
        
        if (File.Exists(_testFilePath))
            File.Delete(_testFilePath);
        
        await _serializer.SaveToFileAsync(person, _testFilePath);
        
        Assert.True(File.Exists(_testFilePath));
        File.Delete(_testFilePath);
    }

    [Fact]
    public async Task LoadFromFileAsync_ShouldReturnPerson()
    {
        var person = new Person("Руслан", "Гунба", 18, "ruslan.gunba@mail.ru", "123123123");
        await _serializer.SaveToFileAsync(person, _testFilePath);
        
        var loaded = await _serializer.LoadFromFileAsync(_testFilePath);
        
        Assert.Equal(person.FirstName, loaded.FirstName);
        Assert.Equal(person.LastName, loaded.LastName);
        
        File.Delete(_testFilePath);
    }

    [Fact]
    public void SaveListToFile_ShouldSaveMultiplePeople()
    {
        var people = new List<Person>
        {
            new("Егор", "Дьяченко", 17, "egor.dyachenko@gmail.com", "123123123"),
            new("Артём", "Ефимов", 18, "artem.efimov@yandex.ru", "123123123")
        };
        
        if (File.Exists(_testListFilePath))
            File.Delete(_testListFilePath);
        
        _serializer.SaveListToFile(people, _testListFilePath);
        
        Assert.True(File.Exists(_testListFilePath));
        File.Delete(_testListFilePath);
    }

    [Fact]
    public void LoadListFromFile_ShouldReturnList()
    {
        var people = new List<Person>
        {
            new("Камиль", "Калимуллин", 17, "kamil.kalimullin@mail.ru", "123123123"),
            new("Денис", "Кашапов", 18, "denis.kashapov@gmail.com", "123123123")
        };
        
        _serializer.SaveListToFile(people, _testListFilePath);
        var loaded = _serializer.LoadListFromFile(_testListFilePath);
        
        Assert.Equal(2, loaded.Count);
        Assert.Equal("Камиль", loaded[0].FirstName);
        Assert.Equal("Денис", loaded[1].FirstName);
        
        File.Delete(_testListFilePath);
    }

    [Fact]
    public void SerializeToJson_ShouldNotIncludePassword()
    {
        var person = new Person("Даниил", "Писарев", 17, "danil.pisarev@yandex.ru", "123123123");
        var json = _serializer.SerializeToJson(person);
        
        Assert.DoesNotContain("123123123", json);
        Assert.DoesNotContain("Password", json);
    }
}

