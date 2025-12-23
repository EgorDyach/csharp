using Xunit;

namespace lab2.Tests;

public class LinkedListTests
{
    [Fact]
    public void AddToEnd_ShouldAddElement()
    {
        var list = new LinkedList<int>();

        list.AddLast(1);
        list.AddLast(2);
        list.AddLast(3);

        Assert.Equal(3, list.Count);
        Assert.Equal(1, list.First!.Value);
        Assert.Equal(3, list.Last!.Value);
    }

    [Fact]
    public void AddToStart_ShouldAddElementAtBeginning()
    {
        var list = new LinkedList<int>();
        list.AddLast(1);
        list.AddLast(2);

        list.AddFirst(0);

        Assert.Equal(3, list.Count);
        Assert.Equal(0, list.First!.Value);
    }

    [Fact]
    public void AddToMiddle_ShouldAddElementInMiddle()
    {
        var list = new LinkedList<int>();
        list.AddLast(1);
        list.AddLast(2);
        list.AddLast(3);
        list.AddLast(4);

        int middleIndex = list.Count / 2;
        var node = list.First;
        for (int i = 0; i < middleIndex; i++)
        {
            node = node?.Next;
        }
        if (node != null)
        {
            list.AddAfter(node, 99);
        }

        Assert.Equal(5, list.Count);
        Assert.Contains(99, list);
    }

    [Fact]
    public void RemoveFromStart_ShouldRemoveFirstElement()
    {
        var list = new LinkedList<int>();
        list.AddLast(1);
        list.AddLast(2);
        list.AddLast(3);

        list.RemoveFirst();

        Assert.Equal(2, list.Count);
        Assert.Equal(2, list.First!.Value);
    }

    [Fact]
    public void RemoveFromEnd_ShouldRemoveLastElement()
    {
        var list = new LinkedList<int>();
        list.AddLast(1);
        list.AddLast(2);
        list.AddLast(3);

        list.RemoveLast();

        Assert.Equal(2, list.Count);
        Assert.Equal(2, list.Last!.Value);
    }

    [Fact]
    public void RemoveFromMiddle_ShouldRemoveMiddleElement()
    {
        var list = new LinkedList<int>();
        list.AddLast(1);
        list.AddLast(2);
        list.AddLast(3);
        list.AddLast(4);
        list.AddLast(5);

        int middleIndex = list.Count / 2;
        var node = list.First;
        for (int i = 0; i < middleIndex; i++)
        {
            node = node?.Next;
        }
        if (node != null)
        {
            list.Remove(node);
        }

        Assert.Equal(4, list.Count);
        Assert.DoesNotContain(3, list);
    }

    [Fact]
    public void FindByValue_ShouldReturnTrueWhenFound()
    {
        var list = new LinkedList<int>();
        list.AddLast(1);
        list.AddLast(2);
        list.AddLast(3);

        var found = list.Contains(2);

        Assert.True(found);
    }

    [Fact]
    public void FindByValue_ShouldReturnFalseWhenNotFound()
    {
        var list = new LinkedList<int>();
        list.AddLast(1);
        list.AddLast(2);
        list.AddLast(3);

        var found = list.Contains(99);

        Assert.False(found);
    }
}

