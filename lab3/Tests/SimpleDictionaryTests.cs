using lab3.Collections;
using Xunit;

namespace lab3.Tests;

public class SimpleDictionaryTests
{
    [Fact]
    public void Add_ShouldIncreaseCount()
    {
        var dict = new SimpleDictionary<string, int>();
        dict.Add("один", 1);
        dict.Add("два", 2);
        
        Assert.Equal(2, dict.Count);
    }

    [Fact]
    public void Indexer_ShouldGetAndSet()
    {
        var dict = new SimpleDictionary<string, int>();
        dict.Add("один", 1);
        
        Assert.Equal(1, dict["один"]);
        
        dict["один"] = 10;
        Assert.Equal(10, dict["один"]);
    }

    [Fact]
    public void ContainsKey_ShouldReturnTrueForExistingKey()
    {
        var dict = new SimpleDictionary<string, int>();
        dict.Add("один", 1);
        
        Assert.True(dict.ContainsKey("один"));
        Assert.False(dict.ContainsKey("два"));
    }

    [Fact]
    public void Remove_ShouldDecreaseCount()
    {
        var dict = new SimpleDictionary<string, int>();
        dict.Add("один", 1);
        dict.Add("два", 2);
        
        bool removed = dict.Remove("один");
        
        Assert.True(removed);
        Assert.Equal(1, dict.Count);
        Assert.False(dict.ContainsKey("один"));
    }

    [Fact]
    public void TryGetValue_ShouldReturnTrueForExistingKey()
    {
        var dict = new SimpleDictionary<string, int>();
        dict.Add("один", 1);
        
        Assert.True(dict.TryGetValue("один", out int value));
        Assert.Equal(1, value);
        
        Assert.False(dict.TryGetValue("два", out _));
    }

    [Fact]
    public void GetEnumerator_ShouldIterateAllItems()
    {
        var dict = new SimpleDictionary<string, int>();
        dict.Add("один", 1);
        dict.Add("два", 2);
        
        var items = new List<KeyValuePair<string, int>>();
        foreach (var kvp in dict)
        {
            items.Add(kvp);
        }
        
        Assert.Equal(2, items.Count);
    }

    [Fact]
    public void Clear_ShouldRemoveAllItems()
    {
        var dict = new SimpleDictionary<string, int>();
        dict.Add("один", 1);
        dict.Add("два", 2);
        
        dict.Clear();
        
        Assert.Equal(0, dict.Count);
    }
}

