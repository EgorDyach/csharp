using lab4.Problems;

namespace lab4;

class Program
{
    static void Main(string[] args)
    {
        Console.WriteLine("=== задача 1: обедающие философы (с deadlock) ===");
        var philosophersWithDeadlock = new DiningPhilosophers();
        philosophersWithDeadlock.StartWithDeadlock();
        Thread.Sleep(2000);
        philosophersWithDeadlock.Stop();
        Console.WriteLine("остановлено");

        Console.WriteLine("\n=== задача 1: обедающие философы (без deadlock) ===");
        var philosophersWithoutDeadlock = new DiningPhilosophers();
        philosophersWithoutDeadlock.StartWithoutDeadlock();
        Thread.Sleep(2000);
        philosophersWithoutDeadlock.Stop();
        var counts = philosophersWithoutDeadlock.GetEatCounts();
        foreach (var kvp in counts)
        {
            Console.WriteLine($"философ {kvp.Key}: поел {kvp.Value} раз");
        }

        Console.WriteLine("\n=== задача 2: спящий парикмахер ===");
        var barber = new SleepingBarber(5);
        barber.Start();

        for (int i = 0; i < 10; i++)
        {
            int customerId = i;
            new Thread(() =>
            {
                if (barber.CustomerArrives(customerId))
                {
                    Console.WriteLine($"клиент {customerId} пришел");
                }
                else
                {
                    Console.WriteLine($"клиент {customerId} ушел (очередь полна)");
                }
            }).Start();
            Thread.Sleep(100);
        }

        Thread.Sleep(3000);
        barber.Stop();
        Console.WriteLine($"обслужено клиентов: {barber.GetCustomersServed()}");

        Console.WriteLine("\n=== задача 3: производитель-потребитель ===");
        var producerConsumer = new ProducerConsumer<int>(5);
        producerConsumer.Start(
            producerCount: 2,
            consumerCount: 3,
            produceItem: (id) => id * 10,
            consumeItem: (item, consumerId) => Console.WriteLine($"потребитель {consumerId} обработал {item}")
        );

        Thread.Sleep(2000);
        producerConsumer.Stop();
        Console.WriteLine($"произведено: {producerConsumer.GetItemsProduced()}, потреблено: {producerConsumer.GetItemsConsumed()}");
    }
}

