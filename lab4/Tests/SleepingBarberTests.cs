using lab4.Problems;
using Xunit;

namespace lab4.Tests;

public class SleepingBarberTests
{
    [Fact]
    public void CustomerArrives_ShouldAcceptCustomer()
    {
        var barber = new SleepingBarber(5);
        barber.Start();
        
        bool accepted = barber.CustomerArrives(1);
        
        Thread.Sleep(500);
        barber.Stop();
        
        Assert.True(accepted);
    }

    [Fact]
    public void CustomerArrives_ShouldRejectWhenFull()
    {
        var barber = new SleepingBarber(2);
        
        barber.CustomerArrives(1);
        barber.CustomerArrives(2);
        
        Assert.Equal(2, barber.GetWaitingRoomCount());
        
        bool rejected = barber.CustomerArrives(3);
        
        Assert.False(rejected);
        Assert.Equal(2, barber.GetWaitingRoomCount());
    }

    [Fact]
    public void GetCustomersServed_ShouldReturnCount()
    {
        var barber = new SleepingBarber(5);
        barber.Start();
        
        for (int i = 0; i < 3; i++)
        {
            barber.CustomerArrives(i);
        }
        
        Thread.Sleep(1000);
        barber.Stop();
        
        Assert.True(barber.GetCustomersServed() > 0);
    }
}

