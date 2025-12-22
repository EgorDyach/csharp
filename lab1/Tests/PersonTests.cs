using lab1.Models;
using Xunit;

namespace lab1.Tests;

public class PersonTests
{
    [Fact]
    public void Email_Setter_ShouldValidateEmail()
    {
        var person = new Person("Арина", "Шалымова", 18, "arina.shalymova@mail.ru", "123123123");
        
        Assert.Throws<ArgumentException>(() => person.Email = "неправильныйemail");
    }

    [Fact]
    public void Email_Setter_ShouldAcceptValidEmail()
    {
        var person = new Person("Арина", "Шалымова", 18, "arina.shalymova@mail.ru", "123123123");
        person.Email = "new.email@mail.ru";
        
        Assert.Equal("new.email@mail.ru", person.Email);
    }

    [Fact]
    public void BirthDate_ShouldGetAndSet()
    {
        var person = new Person("Мария", "Рязанова", 18, "maria.ryazanova@yandex.ru", "123123123");
        var birthDate = new DateTime(2006, 1, 1);
        
        person.BirthDate = birthDate;
        
        Assert.Equal(birthDate, person.BirthDate);
    }

    [Fact]
    public void Id_ShouldSerializeAsPersonId()
    {
        var person = new Person("Дмитрий", "Кривощеков", 17, "dmitry.krivoshchekov@mail.ru", "123123123", "id123");
        
        Assert.Equal("id123", person.Id);
    }

    [Fact]
    public void PhoneNumber_ShouldSerializeAsPhone()
    {
        var person = new Person("Елизавета", "Кобзева", 17, "elizaveta.kobzeva@mail.ru", "123123123", "", null, "+79001234567");
        
        Assert.Equal("+79001234567", person.PhoneNumber);
    }

    [Fact]
    public void Constructor_ShouldThrowExceptionForInvalidEmail()
    {
        Assert.Throws<ArgumentException>(() => 
            new Person("Софья", "Мурина", 17, "неправильныйemail", "123123123"));
    }

    [Fact]
    public void Constructor_ShouldThrowExceptionForNegativeAge()
    {
        Assert.Throws<ArgumentException>(() => 
            new Person("Иван", "Филиппов", -1, "ivan.filippov@mail.ru", "123123123"));
    }

    [Fact]
    public void Constructor_ShouldAcceptValidEmail()
    {
        var person = new Person("Иван", "Филиппов", 17, "ivan.filippov@mail.ru", "123123123");
        Assert.NotNull(person);
        Assert.Equal("ivan.filippov@mail.ru", person.Email);
    }
}

