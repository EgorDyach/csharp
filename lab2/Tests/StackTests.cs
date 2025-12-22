using Xunit;

namespace lab2.Tests;

public class StackTests
{
    [Fact]
    public void AddToEnd_ShouldAddElement()
    {
        var stack = new Stack<int>();

        stack.Push(1);
        stack.Push(2);
        stack.Push(3);

        Assert.Equal(3, stack.Count);
    }

    [Fact]
    public void RemoveFromEnd_ShouldRemoveLastElement()
    {
        var stack = new Stack<int>();
        stack.Push(1);
        stack.Push(2);
        stack.Push(3);

        stack.Pop();

        Assert.Equal(2, stack.Count);
        Assert.Equal(2, stack.Peek());
    }

    [Fact]
    public void FindByValue_ShouldReturnTrueWhenFound()
    {
        var stack = new Stack<int>();
        stack.Push(1);
        stack.Push(2);
        stack.Push(3);

        var found = stack.Contains(2);

        Assert.True(found);
    }

    [Fact]
    public void FindByValue_ShouldReturnFalseWhenNotFound()
    {
        var stack = new Stack<int>();
        stack.Push(1);
        stack.Push(2);
        stack.Push(3);

        var found = stack.Contains(99);

        Assert.False(found);
    }
}

