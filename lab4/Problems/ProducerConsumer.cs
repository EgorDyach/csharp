using System.Collections.Concurrent;

namespace lab4.Problems;

public class ProducerConsumer<T>
{
    private readonly BlockingCollection<T> _buffer;
    private readonly SemaphoreSlim _producerSemaphore;
    private readonly SemaphoreSlim _consumerSemaphore;
    private readonly int _bufferSize;
    private readonly List<Thread> _producers;
    private readonly List<Thread> _consumers;
    private bool _isRunning;
    private int _itemsProduced;
    private int _itemsConsumed;

    public ProducerConsumer(int bufferSize = 5)
    {
        _bufferSize = bufferSize;
        _buffer = new BlockingCollection<T>(boundedCapacity: bufferSize);
        _producerSemaphore = new SemaphoreSlim(bufferSize, bufferSize);
        _consumerSemaphore = new SemaphoreSlim(0, bufferSize);
        _producers = new List<Thread>();
        _consumers = new List<Thread>();
        _isRunning = false;
        _itemsProduced = 0;
        _itemsConsumed = 0;
    }

    public void Start(int producerCount, int consumerCount, Func<int, T> produceItem, Action<T, int> consumeItem)
    {
        if (_isRunning)
            return;

        _isRunning = true;

        for (int i = 0; i < producerCount; i++)
        {
            int producerId = i;
            var producer = new Thread(() => ProducerWork(producerId, produceItem));
            _producers.Add(producer);
            producer.Start();
        }

        for (int i = 0; i < consumerCount; i++)
        {
            int consumerId = i;
            var consumer = new Thread(() => ConsumerWork(consumerId, consumeItem));
            _consumers.Add(consumer);
            consumer.Start();
        }
    }

    public void Stop()
    {
        _isRunning = false;
        _buffer.CompleteAdding();

        foreach (var producer in _producers)
        {
            producer.Join(TimeSpan.FromSeconds(2));
        }

        foreach (var consumer in _consumers)
        {
            consumer.Join(TimeSpan.FromSeconds(2));
        }
    }

    public int GetItemsProduced()
    {
        return _itemsProduced;
    }

    public int GetItemsConsumed()
    {
        return _itemsConsumed;
    }

    private void ProducerWork(int producerId, Func<int, T> produceItem)
    {
        while (_isRunning)
        {
            _producerSemaphore.Wait();

            if (!_isRunning)
                break;

            try
            {
                T item = produceItem(producerId);
                _buffer.Add(item);
                Interlocked.Increment(ref _itemsProduced);
                _consumerSemaphore.Release();
            }
            catch (InvalidOperationException)
            {
                break;
            }
        }
    }

    private void ConsumerWork(int consumerId, Action<T, int> consumeItem)
    {
        while (_isRunning || !_buffer.IsCompleted)
        {
            _consumerSemaphore.Wait();

            if (!_isRunning && _buffer.IsCompleted)
                break;

            try
            {
                if (_buffer.TryTake(out T? item, TimeSpan.FromMilliseconds(100)))
                {
                    consumeItem(item, consumerId);
                    Interlocked.Increment(ref _itemsConsumed);
                    _producerSemaphore.Release();
                }
            }
            catch
            {
            }
        }
    }
}

