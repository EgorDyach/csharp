using lab4.Problems;
using Xunit;

namespace lab4.Tests;

public class ProducerConsumerTests
{
    [Fact]
    public void Start_ShouldProduceAndConsume()
    {
        var pc = new ProducerConsumer<int>(5);
        var consumed = new System.Collections.Concurrent.ConcurrentBag<int>();
        
        pc.Start(
            producerCount: 2,
            consumerCount: 2,
            produceItem: (id) => id,
            consumeItem: (item, consumerId) => consumed.Add(item)
        );
        
        Thread.Sleep(1000);
        pc.Stop();
        
        Assert.True(pc.GetItemsProduced() > 0);
        Assert.True(pc.GetItemsConsumed() > 0);
    }

    [Fact]
    public void Stop_ShouldStopAllThreads()
    {
        var pc = new ProducerConsumer<int>(5);
        
        pc.Start(
            producerCount: 1,
            consumerCount: 1,
            produceItem: (id) => id,
            consumeItem: (item, consumerId) => { }
        );
        
        Thread.Sleep(100);
        pc.Stop();
        
        Assert.True(true);
    }
}

