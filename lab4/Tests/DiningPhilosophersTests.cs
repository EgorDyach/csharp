using lab4.Problems;
using Xunit;

namespace lab4.Tests;

public class DiningPhilosophersTests
{
    [Fact]
    public void StartWithoutDeadlock_ShouldNotDeadlock()
    {
        var philosophers = new DiningPhilosophers();
        philosophers.StartWithoutDeadlock();
        
        Thread.Sleep(1000);
        
        philosophers.Stop();
        var counts = philosophers.GetEatCounts();
        
        Assert.True(counts.Values.Sum() > 0);
    }

    [Fact]
    public void GetEatCounts_ShouldReturnCounts()
    {
        var philosophers = new DiningPhilosophers();
        philosophers.StartWithoutDeadlock();
        
        Thread.Sleep(500);
        
        philosophers.Stop();
        var counts = philosophers.GetEatCounts();
        
        Assert.Equal(5, counts.Count);
    }
}

