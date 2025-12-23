using System.Collections.Concurrent;

namespace lab4.Problems;

public class SleepingBarber
{
    private readonly SemaphoreSlim _barberSemaphore;
    private readonly SemaphoreSlim _customerSemaphore;
    private readonly Mutex _mutex;
    private readonly ConcurrentQueue<int> _waitingRoom;
    private readonly int _maxWaitingRoomSize;
    private Thread? _barberThread;
    private bool _isRunning;
    private int _customersServed;

    public SleepingBarber(int maxWaitingRoomSize = 5)
    {
        _maxWaitingRoomSize = maxWaitingRoomSize;
        _barberSemaphore = new SemaphoreSlim(0, 1);
        _customerSemaphore = new SemaphoreSlim(0);
        _mutex = new Mutex();
        _waitingRoom = new ConcurrentQueue<int>();
        _isRunning = false;
        _customersServed = 0;
    }

    public void Start()
    {
        if (_isRunning)
            return;

        _isRunning = true;
        _barberThread = new Thread(BarberWork);
        _barberThread.Start();
    }

    public void Stop()
    {
        _isRunning = false;
        try
        {
            _barberSemaphore.Release();
        }
        catch (SemaphoreFullException)
        {
        }
        _barberThread?.Join(TimeSpan.FromSeconds(2));
    }

    public bool CustomerArrives(int customerId)
    {
        _mutex.WaitOne();
        try
        {
            if (_waitingRoom.Count >= _maxWaitingRoomSize)
            {
                return false;
            }

            bool wasEmpty = _waitingRoom.Count == 0;
            _waitingRoom.Enqueue(customerId);
            
            if (wasEmpty)
            {
                try
                {
                    _barberSemaphore.Release();
                }
                catch (SemaphoreFullException)
                {
                }
            }
            
            return true;
        }
        finally
        {
            _mutex.ReleaseMutex();
        }
    }

    public int GetCustomersServed()
    {
        return _customersServed;
    }

    public int GetWaitingRoomCount()
    {
        _mutex.WaitOne();
        try
        {
            return _waitingRoom.Count;
        }
        finally
        {
            _mutex.ReleaseMutex();
        }
    }

    private void BarberWork()
    {
        while (_isRunning)
        {
            _barberSemaphore.Wait();

            if (!_isRunning)
                break;

            while (true)
            {
                _mutex.WaitOne();
                try
                {
                    if (_waitingRoom.TryDequeue(out int customerId))
                    {
                        _mutex.ReleaseMutex();
                        CutHair(customerId);
                        _customersServed++;
                    }
                    else
                    {
                        _mutex.ReleaseMutex();
                        break;
                    }
                }
                catch
                {
                    _mutex.ReleaseMutex();
                    break;
                }
            }
        }
    }

    private void CutHair(int customerId)
    {
        Thread.Sleep(Random.Shared.Next(100, 300));
    }
}

