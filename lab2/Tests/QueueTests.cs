using Xunit;

namespace lab2.Tests;

public class QueueTests
{
    [Fact]
    public void AddToEnd_ShouldAddElement()
    {
        var queue = new Queue<int>();

        queue.Enqueue(1);
        queue.Enqueue(2);
        queue.Enqueue(3);

        Assert.Equal(3, queue.Count);
    }

    [Fact]
    public void RemoveFromStart_ShouldRemoveFirstElement()
    {
        var queue = new Queue<int>();
        queue.Enqueue(1);
        queue.Enqueue(2);
        queue.Enqueue(3);

        queue.Dequeue();

        Assert.Equal(2, queue.Count);
        Assert.Equal(2, queue.Peek());
    }

    [Fact]
    public void FindByValue_ShouldReturnTrueWhenFound()
    {
        var queue = new Queue<int>();
        queue.Enqueue(1);
        queue.Enqueue(2);
        queue.Enqueue(3);

        var found = queue.Contains(2);

        Assert.True(found);
    }

    [Fact]
    public void FindByValue_ShouldReturnFalseWhenNotFound()
    {
        var queue = new Queue<int>();
        queue.Enqueue(1);
        queue.Enqueue(2);
        queue.Enqueue(3);

        var found = queue.Contains(99);

        Assert.False(found);
    }
}

