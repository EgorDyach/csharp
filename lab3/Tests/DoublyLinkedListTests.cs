using lab3.Collections;
using Xunit;

namespace lab3.Tests;

public class DoublyLinkedListTests
{
    [Fact]
    public void Add_ShouldIncreaseCount()
    {
        var list = new DoublyLinkedList<int>();
        list.Add(1);
        list.Add(2);
        
        Assert.Equal(2, list.Count);
    }

    [Fact]
    public void Indexer_ShouldGetAndSet()
    {
        var list = new DoublyLinkedList<int>();
        list.Add(1);
        list.Add(2);
        
        Assert.Equal(1, list[0]);
        Assert.Equal(2, list[1]);
        
        list[0] = 10;
        Assert.Equal(10, list[0]);
    }

    [Fact]
    public void Remove_ShouldDecreaseCount()
    {
        var list = new DoublyLinkedList<int>();
        list.Add(1);
        list.Add(2);
        list.Add(3);
        
        bool removed = list.Remove(2);
        
        Assert.True(removed);
        Assert.Equal(2, list.Count);
        Assert.False(list.Contains(2));
    }

    [Fact]
    public void Contains_ShouldReturnTrueForExistingItem()
    {
        var list = new DoublyLinkedList<int>();
        list.Add(1);
        list.Add(2);
        
        Assert.True(list.Contains(1));
        Assert.False(list.Contains(3));
    }

    [Fact]
    public void IndexOf_ShouldReturnCorrectIndex()
    {
        var list = new DoublyLinkedList<int>();
        list.Add(1);
        list.Add(2);
        list.Add(3);
        
        Assert.Equal(1, list.IndexOf(2));
        Assert.Equal(-1, list.IndexOf(4));
    }

    [Fact]
    public void Insert_ShouldAddAtSpecifiedIndex()
    {
        var list = new DoublyLinkedList<int>();
        list.Add(1);
        list.Add(3);
        
        list.Insert(1, 2);
        
        Assert.Equal(3, list.Count);
        Assert.Equal(2, list[1]);
    }

    [Fact]
    public void Clear_ShouldRemoveAllItems()
    {
        var list = new DoublyLinkedList<int>();
        list.Add(1);
        list.Add(2);
        
        list.Clear();
        
        Assert.Equal(0, list.Count);
    }

    [Fact]
    public void GetEnumerator_ShouldIterateAllItems()
    {
        var list = new DoublyLinkedList<int>();
        list.Add(1);
        list.Add(2);
        list.Add(3);
        
        var items = new List<int>();
        foreach (var item in list)
        {
            items.Add(item);
        }
        
        Assert.Equal(3, items.Count);
        Assert.Equal(1, items[0]);
        Assert.Equal(2, items[1]);
        Assert.Equal(3, items[2]);
    }
}

