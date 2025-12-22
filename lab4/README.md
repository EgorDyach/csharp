# Лабораторная работа 4: Синхронизация потоков

## Цель работы

Изучить проблему синхронизации потоков, научиться выявлять и предотвращать взаимоблокировки (deadlock).

## Реализованные задачи

### 1. Обедающие философы (Dining Philosophers)

**Проблема:** 5 философов сидят за круглым столом, между каждыми двумя философами лежит одна вилка. Для еды нужны две вилки (левая и правая).

**Реализовано:**
- Версия с deadlock (`StartWithDeadlock`) - демонстрирует проблему взаимоблокировки
- Версия без deadlock (`StartWithoutDeadlock`) - исправленная версия с упорядочиванием вилок

**Решение без deadlock:**
- Вилки всегда берутся в определенном порядке (сначала вилка с меньшим номером, затем с большим)
- Это предотвращает циклическую зависимость, которая приводит к deadlock

### 2. Задача о спящем парикмахере (Sleeping Barber)

**Описание:**
- Парикмахер спит, если клиентов нет
- Когда приходит клиент, парикмахер просыпается и работает
- Очередь в зале ожидания ограничена

**Реализация:**
- Использует `SemaphoreSlim` для синхронизации парикмахера и клиентов
- Использует `Mutex` для защиты очереди
- `ConcurrentQueue` для хранения клиентов

### 3. Производитель-Потребитель (Producer-Consumer)

**Описание:**
- Есть буфер ограниченного размера
- Производители добавляют товары в буфер
- Потребители забирают товары из буфера

**Реализация:**
- Использует `BlockingCollection<T>` для безопасной работы с буфером
- `SemaphoreSlim` для контроля заполненности буфера
- Предотвращает переполнение буфера и чтение из пустого буфера

## Структура проекта

```
lab4/
├── Problems/
│   ├── DiningPhilosophers.cs
│   ├── SleepingBarber.cs
│   └── ProducerConsumer.cs
├── Tests/
│   ├── DiningPhilosophersTests.cs
│   ├── SleepingBarberTests.cs
│   └── ProducerConsumerTests.cs
├── Program.cs
└── README.md
```

## Запуск проекта

### Сборка проекта
```bash
dotnet build
```

### Запуск приложения
```bash
dotnet run --project lab4.csproj
```

### Запуск тестов
```bash
dotnet test
```

## Примеры использования

### Обедающие философы
```csharp
var philosophers = new DiningPhilosophers();
philosophers.StartWithoutDeadlock();
Thread.Sleep(2000);
philosophers.Stop();
```

### Спящий парикмахер
```csharp
var barber = new SleepingBarber(5);
barber.Start();
barber.CustomerArrives(1);
Thread.Sleep(1000);
barber.Stop();
```

### Производитель-Потребитель
```csharp
var pc = new ProducerConsumer<int>(5);
pc.Start(2, 3, 
    produceItem: (id) => id * 10,
    consumeItem: (item, consumerId) => Console.WriteLine(item)
);
Thread.Sleep(2000);
pc.Stop();
```

## Вопросы для защиты

1. Что такое race condition (состояние гонки)? Приведите пример из вашей задачи.
2. Чем deadlock отличается от starvation? Где может возникнуть каждое из этих явлений в вашей реализации?
3. Что такое критическая секция? Где она находится в вашем коде?
4. Объясните разницу между:
   - lock и Monitor
   - Mutex и SemaphoreSlim
   - Semaphore и SemaphoreSlim

