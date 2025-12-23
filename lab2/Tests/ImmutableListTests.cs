using Xunit;
using System.Collections.Immutable;

namespace lab2.Tests;

public class ImmutableListTests
{
    [Fact]
    public void GetByIndex_ShouldReturnCorrectElement()
    {
        var list = ImmutableList<int>.Empty;
        list = list.Add(10);
        list = list.Add(20);
        list = list.Add(30);
        list = list.Add(40);
        list = list.Add(50);

        var value = list[2];

        Assert.Equal(30, value);
    }

    [Fact]
    public void FindByValue_ShouldReturnTrueWhenFound()
    {
        var list = ImmutableList<int>.Empty;
        list = list.Add(1);
        list = list.Add(2);
        list = list.Add(3);

        var found = list.Contains(2);

        Assert.True(found);
    }

    [Fact]
    public void FindByValue_ShouldReturnFalseWhenNotFound()
    {
        var list = ImmutableList<int>.Empty;
        list = list.Add(1);
        list = list.Add(2);
        list = list.Add(3);

        var found = list.Contains(99);

        Assert.False(found);
    }

    [Fact]
    public void OperationsShouldNotModifyOriginal()
    {
        var originalList = ImmutableList<int>.Empty;
        originalList = originalList.Add(1);
        originalList = originalList.Add(2);
        originalList = originalList.Add(3);

        var newList = originalList.Add(4);
        var anotherList = originalList.Remove(2);

        Assert.Equal(3, originalList.Count);
        Assert.Equal(4, newList.Count);
        Assert.Equal(2, anotherList.Count);
        Assert.Contains(2, originalList);
        Assert.DoesNotContain(2, anotherList);
    }
}

