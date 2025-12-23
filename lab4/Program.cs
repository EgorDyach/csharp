using lab4.Problems;

namespace lab4;

class Program
{
    static void Main(string[] args)
    {
        Console.WriteLine("Философы с deadlock");
        var philosophersWithDeadlock = new DiningPhilosophers();
        philosophersWithDeadlock.StartWithDeadlock();
        Thread.Sleep(2000);
        philosophersWithDeadlock.Stop();
        Console.WriteLine("Стоп");

        Console.WriteLine("\nФилософы без deadlock");
        var philosophersWithoutDeadlock = new DiningPhilosophers();
        philosophersWithoutDeadlock.StartWithoutDeadlock();
        Thread.Sleep(2000);
        philosophersWithoutDeadlock.Stop();
        var counts = philosophersWithoutDeadlock.GetEatCounts();
        foreach (var kvp in counts)
        {
            Console.WriteLine($"Философ {kvp.Key} поел {kvp.Value} раз");
        }

        Console.WriteLine("\nПарикмахер");
        var barber = new SleepingBarber(5);
        barber.Start();

        for (int i = 0; i < 10; i++)
        {
            int customerId = i;
            new Thread(() =>
            {
                if (barber.CustomerArrives(customerId))
                {
                    Console.WriteLine($"Клиент {customerId} зашел");
                }
                else
                {
                    Console.WriteLine($"Клиент {customerId} ушел - нет места");
                }
            }).Start();
            Thread.Sleep(100);
        }

        Thread.Sleep(3000);
        barber.Stop();
        Console.WriteLine($"Обслужено: {barber.GetCustomersServed()}");

        Console.WriteLine("\nПроизводитель-потребитель");
        var producerConsumer = new ProducerConsumer<int>(5);
        producerConsumer.Start(
            producerCount: 2,
            consumerCount: 3,
            produceItem: (id) => id * 10,
            consumeItem: (item, consumerId) => Console.WriteLine($"Потребитель {consumerId} взял {item}")
        );

        Thread.Sleep(2000);
        producerConsumer.Stop();
        Console.WriteLine($"Произведено: {producerConsumer.GetItemsProduced()}, потреблено: {producerConsumer.GetItemsConsumed()}");
    }
}

