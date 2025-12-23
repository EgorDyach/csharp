using lab1.Services;
using Xunit;

namespace lab1.Tests;

public class FileResourceManagerTests
{
    private readonly string _testFilePath = "test_resource.txt";

    [Fact]
    public void OpenForWriting_ShouldCreateFile()
    {
        if (File.Exists(_testFilePath))
            File.Delete(_testFilePath);

        using var manager = new FileResourceManager(_testFilePath, FileMode.Create);
        manager.OpenForWriting();
        manager.WriteLine("test");

        Assert.True(File.Exists(_testFilePath));
        File.Delete(_testFilePath);
    }

    [Fact]
    public void WriteLine_ShouldWriteText()
    {
        if (File.Exists(_testFilePath))
            File.Delete(_testFilePath);

        using var manager = new FileResourceManager(_testFilePath, FileMode.Create);
        manager.OpenForWriting();
        manager.WriteLine("hello, world!");

        var content = File.ReadAllText(_testFilePath);
        Assert.Contains("hello, world!", content);
        File.Delete(_testFilePath);
    }

    [Fact]
    public void ReadAllText_ShouldReadFile()
    {
        File.WriteAllText(_testFilePath, "test");

        using var manager = new FileResourceManager(_testFilePath, FileMode.Open);
        manager.OpenForReading();
        var content = manager.ReadAllText();

        Assert.Equal("test", content.Trim());
        File.Delete(_testFilePath);
    }

    [Fact]
    public void AppendText_ShouldAppendToFile()
    {
        if (File.Exists(_testFilePath))
            File.Delete(_testFilePath);

        using var manager = new FileResourceManager(_testFilePath, FileMode.Create);
        manager.OpenForWriting();
        manager.AppendText("initial text");
        manager.AppendText("added text");

        var content = File.ReadAllText(_testFilePath);
        Assert.Contains("initial text", content);
        Assert.Contains("added text", content);
        File.Delete(_testFilePath);
    }

    [Fact]
    public void GetFileInfo_ShouldReturnFileInfo()
    {
        File.WriteAllText(_testFilePath, "Test");

        using var manager = new FileResourceManager(_testFilePath, FileMode.Open);
        var info = manager.GetFileInfo();

        Assert.NotNull(info);
        Assert.True(info.Exists);
        File.Delete(_testFilePath);
    }

    [Fact]
    public void Dispose_ShouldCloseResources()
    {
        using var manager = new FileResourceManager(_testFilePath, FileMode.Create);
        manager.OpenForWriting();
        manager.WriteLine("Test");
    }

    [Fact]
    public void OpenForReading_ShouldThrowIfFileNotExists()
    {
        if (File.Exists(_testFilePath))
            File.Delete(_testFilePath);

        using var manager = new FileResourceManager(_testFilePath, FileMode.Open);
        var exception = Assert.Throws<IOException>(() => manager.OpenForReading());
        Assert.Contains("файл не найден", exception.Message);
    }
}

