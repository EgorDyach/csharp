using Xunit;

namespace lab2.Tests;

public class ListTests
{
    [Fact]
    public void AddToEnd_ShouldAddElement()
    {
        var list = new List<int>();

        list.Add(1);
        list.Add(2);
        list.Add(3);

        Assert.Equal(3, list.Count);
        Assert.Equal(1, list[0]);
        Assert.Equal(2, list[1]);
        Assert.Equal(3, list[2]);
    }

    [Fact]
    public void AddToStart_ShouldAddElementAtBeginning()
    {
        var list = new List<int> { 1, 2, 3 };

        list.Insert(0, 0);

        Assert.Equal(4, list.Count);
        Assert.Equal(0, list[0]);
        Assert.Equal(1, list[1]);
    }

    [Fact]
    public void AddToMiddle_ShouldAddElementInMiddle()
    {
        var list = new List<int> { 1, 2, 3, 4 };

        int middleIndex = list.Count / 2;
        list.Insert(middleIndex, 99);

        Assert.Equal(5, list.Count);
        Assert.Equal(99, list[2]); // Middle index
    }

    [Fact]
    public void RemoveFromStart_ShouldRemoveFirstElement()
    {
        var list = new List<int> { 1, 2, 3, 4 };

        list.RemoveAt(0);

        Assert.Equal(3, list.Count);
        Assert.Equal(2, list[0]);
    }

    [Fact]
    public void RemoveFromEnd_ShouldRemoveLastElement()
    {
        var list = new List<int> { 1, 2, 3, 4 };

        list.RemoveAt(list.Count - 1);

        Assert.Equal(3, list.Count);
        Assert.Equal(3, list[2]);
    }

    [Fact]
    public void RemoveFromMiddle_ShouldRemoveMiddleElement()
    {
        var list = new List<int> { 1, 2, 3, 4, 5 };

        int middleIndex = list.Count / 2;
        list.RemoveAt(middleIndex);

        Assert.Equal(4, list.Count);
        Assert.DoesNotContain(3, list);
    }

    [Fact]
    public void FindByValue_ShouldReturnTrueWhenFound()
    {
        var list = new List<int> { 1, 2, 3, 4, 5 };

        var found = list.Contains(3);

        Assert.True(found);
    }

    [Fact]
    public void FindByValue_ShouldReturnFalseWhenNotFound()
    {
        var list = new List<int> { 1, 2, 3, 4, 5 };

        var found = list.Contains(99);

        Assert.False(found);
    }

    [Fact]
    public void GetByIndex_ShouldReturnCorrectElement()
    {
        var list = new List<int> { 10, 20, 30, 40, 50 };

        var value = list[2];

        Assert.Equal(30, value);
    }
}

