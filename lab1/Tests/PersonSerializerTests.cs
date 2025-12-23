using System;
using System.IO;
using lab1.Models;
using lab1.Services;
using Xunit;

namespace lab1.Tests;

public class PersonSerializerTests : IDisposable
{
    private readonly PersonSerializer _serializer = new();
    private readonly string _testDirectory;
    private readonly string _testFilePath;
    private readonly string _testListFilePath;

    public PersonSerializerTests()
    {
        _testDirectory = Path.Combine(Path.GetTempPath(), "lab1_tests", Guid.NewGuid().ToString());
        Directory.CreateDirectory(_testDirectory);
        _testFilePath = Path.Combine(_testDirectory, "test_person.json");
        _testListFilePath = Path.Combine(_testDirectory, "test_people.json");
    }

    public void Dispose()
    {
        if (Directory.Exists(_testDirectory))
        {
            Directory.Delete(_testDirectory, true);
        }
    }

    [Fact]
    public void SerializeToJson_ShouldReturnValidJson()
    {
        var person = new Person("Анастасия", "Гордиенко", 18, "anastasia.gordienko@gmail.com", "123123123", "id001");
        var json = _serializer.SerializeToJson(person);
        
        Assert.NotNull(json);
        
        var deserialized = _serializer.DeserializeFromJson(json);
        Assert.NotNull(deserialized);
        Assert.Equal("Анастасия", deserialized.FirstName);
        Assert.Equal("Гордиенко", deserialized.LastName);
        Assert.DoesNotContain("123123123", json);
        Assert.Contains("personId", json);
    }

    [Fact]
    public void DeserializeFromJson_ShouldReturnValidPerson()
    {
        var json = "{\"firstName\":\"Владислав\",\"lastName\":\"Ганьшин\",\"age\":17,\"email\":\"vladislav.ganshin@yandex.ru\",\"personId\":\"id001\",\"_birthDate\":\"2007-01-01T00:00:00\",\"phone\":\"+79001234567\"}";
        var person = _serializer.DeserializeFromJson(json);
        
        Assert.NotNull(person);
        Assert.Equal("Владислав", person.FirstName);
        Assert.Equal("Ганьшин", person.LastName);
        Assert.Equal(17, person.Age);
        Assert.Equal("vladislav.ganshin@yandex.ru", person.Email);
        Assert.Equal("id001", person.Id);
        Assert.Equal(new DateTime(2007, 1, 1), person.BirthDate);
        Assert.Equal("+79001234567", person.PhoneNumber);
    }

    [Fact]
    public void SaveToFile_ShouldCreateFile()
    {
        var person = new Person("Дарья", "Горбунова", 17, "darya.gorbunova@mail.ru", "123123123", "id002");
        
        if (File.Exists(_testFilePath))
            File.Delete(_testFilePath);
        
        _serializer.SaveToFile(person, _testFilePath);
        
        Assert.True(File.Exists(_testFilePath));
        File.Delete(_testFilePath);
    }

    [Fact]
    public void LoadFromFile_ShouldReturnPerson()
    {
        var person = new Person("Кирилл", "Баранов", 18, "kirill.baranov@gmail.com", "123123123", "id003");
        _serializer.SaveToFile(person, _testFilePath);
        
        var loaded = _serializer.LoadFromFile(_testFilePath);
        
        Assert.Equal(person.FirstName, loaded.FirstName);
        Assert.Equal(person.LastName, loaded.LastName);
        Assert.Equal(person.Age, loaded.Age);
        Assert.Equal(person.Email, loaded.Email);
        Assert.Equal(person.Id, loaded.Id);
        
        File.Delete(_testFilePath);
    }

    [Fact]
    public async Task SaveToFileAsync_ShouldCreateFile()
    {
        var person = new Person("Ника", "Васильева", 17, "nika.vasilieva@yandex.ru", "123123123", "id004");
        
        if (File.Exists(_testFilePath))
            File.Delete(_testFilePath);
        
        await _serializer.SaveToFileAsync(person, _testFilePath);
        
        Assert.True(File.Exists(_testFilePath));
        File.Delete(_testFilePath);
    }

    [Fact]
    public async Task LoadFromFileAsync_ShouldReturnPerson()
    {
        var person = new Person("Руслан", "Гунба", 18, "ruslan.gunba@mail.ru", "123123123", "id005");
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
            new("Егор", "Дьяченко", 17, "egor.dyachenko@gmail.com", "123123123", "id006"),
            new("Артём", "Ефимов", 18, "artem.efimov@yandex.ru", "123123123", "id007")
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
            new("Камиль", "Калимуллин", 17, "kamil.kalimullin@mail.ru", "123123123", "id008"),
            new("Денис", "Кашапов", 18, "denis.kashapov@gmail.com", "123123123", "id009")
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
        var person = new Person("Даниил", "Писарев", 17, "danil.pisarev@yandex.ru", "123123123", "id010");
        var json = _serializer.SerializeToJson(person);
        
        Assert.DoesNotContain("123123123", json);
        Assert.DoesNotContain("Password", json);
    }

    [Fact]
    public void SerializeToJson_ShouldIncludePersonId()
    {
        var person = new Person("Арина", "Шалымова", 18, "arina.shalymova@mail.ru", "123123123", "id011");
        var json = _serializer.SerializeToJson(person);
        
        Assert.Contains("personId", json);
        Assert.Contains("id011", json);
    }

    [Fact]
    public void SerializeToJson_ShouldIncludeBirthDate()
    {
        var birthDate = new DateTime(2006, 6, 15);
        var person = new Person("Мария", "Рязанова", 18, "maria.ryazanova@yandex.ru", "123123123", "id012", birthDate);
        var json = _serializer.SerializeToJson(person);
        
        Assert.Contains("_birthDate", json);
    }

    [Fact]
    public void SerializeToJson_ShouldIncludePhoneAsPhone()
    {
        var person = new Person("Дмитрий", "Кривощеков", 17, "dmitry.krivoshchekov@mail.ru", "123123123", "id013", null, "+79001234567");
        var json = _serializer.SerializeToJson(person);
        
        Assert.Contains("phone", json);
        
        var deserialized = _serializer.DeserializeFromJson(json);
        Assert.Equal("+79001234567", deserialized.PhoneNumber);
    }
}

