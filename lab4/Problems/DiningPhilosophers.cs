using System.Collections.Concurrent;

namespace lab4.Problems;

public class DiningPhilosophers
{
    private const int PhilosopherCount = 5;
    private readonly object[] _forks;
    private readonly Thread[] _philosophers;
    private readonly CancellationTokenSource _cancellationTokenSource;
    private readonly ConcurrentDictionary<int, int> _eatCount;

    public DiningPhilosophers()
    {
        _forks = new object[PhilosopherCount];
        _philosophers = new Thread[PhilosopherCount];
        _cancellationTokenSource = new CancellationTokenSource();
        _eatCount = new ConcurrentDictionary<int, int>();

        for (int i = 0; i < PhilosopherCount; i++)
        {
            _forks[i] = new object();
            _eatCount[i] = 0;
        }
    }

    public void StartWithDeadlock()
    {
        for (int i = 0; i < PhilosopherCount; i++)
        {
            int philosopherId = i;
            _philosophers[i] = new Thread(() => PhilosopherWithDeadlock(philosopherId, _cancellationTokenSource.Token));
            _philosophers[i].Start();
        }
    }

    public void StartWithoutDeadlock()
    {
        for (int i = 0; i < PhilosopherCount; i++)
        {
            int philosopherId = i;
            _philosophers[i] = new Thread(() => PhilosopherWithoutDeadlock(philosopherId, _cancellationTokenSource.Token));
            _philosophers[i].Start();
        }
    }

    public void Stop()
    {
        _cancellationTokenSource.Cancel();
        foreach (var philosopher in _philosophers)
        {
            philosopher.Join(TimeSpan.FromSeconds(2));
        }
    }

    public Dictionary<int, int> GetEatCounts()
    {
        return _eatCount.ToDictionary(kvp => kvp.Key, kvp => kvp.Value);
    }

    private void PhilosopherWithDeadlock(int id, CancellationToken cancellationToken)
    {
        int leftFork = id;
        int rightFork = (id + 1) % PhilosopherCount;

        while (!cancellationToken.IsCancellationRequested)
        {
            Think(id);

            lock (_forks[leftFork])
            {
                Thread.Sleep(10);
                lock (_forks[rightFork])
                {
                    Eat(id);
                    _eatCount[id]++;
                }
            }
        }
    }

    private void PhilosopherWithoutDeadlock(int id, CancellationToken cancellationToken)
    {
        int leftFork = id;
        int rightFork = (id + 1) % PhilosopherCount;

        int firstFork = Math.Min(leftFork, rightFork);
        int secondFork = Math.Max(leftFork, rightFork);

        while (!cancellationToken.IsCancellationRequested)
        {
            Think(id);

            lock (_forks[firstFork])
            {
                Thread.Sleep(10);
                lock (_forks[secondFork])
                {
                    Eat(id);
                    _eatCount[id]++;
                }
            }
        }
    }

    private void Think(int id)
    {
        Thread.Sleep(Random.Shared.Next(50, 150));
    }

    private void Eat(int id)
    {
        Thread.Sleep(Random.Shared.Next(50, 150));
    }
}

