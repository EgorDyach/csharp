# Лабораторная работа 1: Сериализация JSON, управление ресурсами и работа с файлами в C#

## Цели работы

1. Освоить использование атрибутов JSON для управления процессом сериализации/десериализации
2. Изучить паттерн IDisposable для корректного освобождения ресурсов
3. Научиться работать с файловой системой (чтение/запись файлов)
4. Реализовать сохранение и загрузку объектов в/из файлов JSON
5. Понимать разницу между явным освобождением ресурсов через Dispose() и автоматическим через финализатор

## Структура проекта

```
lab1/
├── Models/
│   └── Person.cs              # Класс Person с атрибутами JSON
├── Services/
│   ├── PersonSerializer.cs    # Менеджер сериализации
│   └── FileResourceManager.cs # Менеджер файловых ресурсов с IDisposable
├── Tests/
│   ├── PersonTests.cs
│   ├── PersonSerializerTests.cs
│   └── FileResourceManagerTests.cs
├── Program.cs
└── README.md
```

## Реализованные компоненты

### 1. Класс Person

Класс `Person` содержит:
- `FirstName`, `LastName`, `Age`, `Email` - свойства с атрибутами JSON
- `Password` - свойство с атрибутом `[JsonIgnore]`
- `FullName` - свойство только для чтения (конкатенация FirstName + LastName)
- `IsAdult` - свойство только для чтения (Age >= 18)
- Валидация Email (проверка наличия '@')

### 2. PersonSerializer

Класс `PersonSerializer` реализует:
- `SerializeToJson(Person person)` - сериализация в строку
- `DeserializeFromJson(string json)` - десериализация из строки
- `SaveToFile(Person person, string filePath)` - сохранение в файл (синхронно)
- `LoadFromFile(string filePath)` - загрузка из файла (синхронно)
- `SaveToFileAsync(Person person, string filePath)` - сохранение в файл (асинхронно)
- `LoadFromFileAsync(string filePath)` - загрузка из файла (асинхронно)
- `SaveListToFile(List<Person> people, string filePath)` - экспорт нескольких объектов
- `LoadListFromFile(string filePath)` - импорт из файла

Особенности:
- Использует UTF-8 кодировку
- Красивое форматирование JSON (WriteIndented = true)
- Обработка исключений
- Логирование ошибок в файл errors.log

### 3. FileResourceManager

Класс `FileResourceManager` реализует `IDisposable` и содержит:
- `FileStream _fileStream` - для работы с файлом
- `StreamWriter _writer` / `StreamReader _reader` - для текстовых операций
- `bool _disposed` - флаг освобождения
- `string _filePath` - путь к файлу

Методы:
- `OpenForWriting()` - открывает файл для записи
- `OpenForReading()` - открывает файл для чтения
- `WriteLine(string text)` - записывает строку в файл
- `ReadAllText()` - читает весь файл
- `AppendText(string text)` - добавляет текст в конец файла
- `GetFileInfo()` - возвращает информацию о файле
- Правильная реализация `IDisposable` с финализатором

Особенности:
- Использование `using` для вложенных ресурсов
- Обработка исключений при работе с файлами
- Проверка существования файла перед операциями
- Потокобезопасность через lock

## Запуск проекта

### Сборка проекта
```bash
dotnet build
```

### Запуск приложения
```bash
dotnet run --project lab1.csproj
```

### Запуск тестов
```bash
dotnet test
```

## Примеры использования

### Сериализация Person
```csharp
var person = new Person("John", "Doe", 25, "john@example.com", "password123");
var serializer = new PersonSerializer();
var json = serializer.SerializeToJson(person);
```

### Сохранение в файл
```csharp
serializer.SaveToFile(person, "person.json");
```

### Загрузка из файла
```csharp
var loadedPerson = serializer.LoadFromFile("person.json");
```

### Работа с FileResourceManager
```csharp
using var manager = new FileResourceManager("file.txt", FileMode.Create);
manager.OpenForWriting();
manager.WriteLine("Hello World");
```

## Вопросы для защиты

1. Почему файловые потоки нужно обязательно закрывать?
2. В чем разница между FileMode.Open и FileMode.Create?
3. Зачем нужен StreamWriter поверх FileStream?
4. Как обрабатывать ситуации, когда файл занят другим процессом?
5. Почему асинхронные операции предпочтительнее для работы с файлами?
6. Как сериализовать объект с приватными полями?
7. Что такое JsonSerializerOptions и зачем они нужны?
8. Как обеспечить атомарность операций записи в файл?
9. Почему поле Password помечено [JsonIgnore]?
10. В чем разница между Dispose() и финализатором?
11. Что произойдет, если использовать объект после вызова Dispose()?
12. Почему в методе Dispose(bool) нужно проверять параметр disposing?
13. Зачем вызывать GC.SuppressFinalize(this) в Dispose()?

