using lab1.Models;
using Xunit;

namespace lab1.Tests;

public class PersonTests
{
    [Fact]
    public void FullName_ShouldConcatenateFirstNameAndLastName()
    {
        var person = new Person("Арина", "Шалымова", 18, "arina.shalymova@mail.ru", "123123123");
        Assert.Equal("Арина Шалымова", person.FullName);
    }

    [Fact]
    public void IsAdult_ShouldReturnTrueForAge18()
    {
        var person = new Person("Мария", "Рязанова", 18, "maria.ryazanova@yandex.ru", "123123123");
        Assert.True(person.IsAdult);
    }

    [Fact]
    public void IsAdult_ShouldReturnFalseForAge17()
    {
        var person = new Person("Дмитрий", "Кривощеков", 17, "dmitry.krivoshchekov@mail.ru", "123123123");
        Assert.False(person.IsAdult);
    }

    [Fact]
    public void Constructor_ShouldThrowExceptionForInvalidEmail()
    {
        Assert.Throws<ArgumentException>(() => 
            new Person("Елизавета", "Кобзева", 17, "неправильныйemail", "123123123"));
    }

    [Fact]
    public void Constructor_ShouldThrowExceptionForNegativeAge()
    {
        Assert.Throws<ArgumentException>(() => 
            new Person("Софья", "Мурина", -1, "sofya.murina@mail.ru", "123123123"));
    }

    [Fact]
    public void Constructor_ShouldAcceptValidEmail()
    {
        var person = new Person("Иван", "Филиппов", 17, "ivan.filippov@mail.ru", "123123123");
        Assert.NotNull(person);
        Assert.Equal("ivan.filippov@mail.ru", person.Email);
    }
}

