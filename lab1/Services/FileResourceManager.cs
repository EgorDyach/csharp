using System.Text;

namespace lab1.Services;

public class FileResourceManager : IDisposable
{
    private FileStream? _fileStream;
    private StreamWriter? _writer;
    private StreamReader? _reader;
    private bool _disposed = false;
    private readonly string _filePath;
    private readonly object _lockObject = new();

    public FileResourceManager(string filePath, FileMode fileMode)
    {
        if (string.IsNullOrWhiteSpace(filePath))
            throw new ArgumentException("путь к файлу не пустой должен быть", nameof(filePath));

        _filePath = filePath;
    }

    public void OpenForWriting()
    {
        ThrowIfDisposed();

        lock (_lockObject)
        {
            try
            {
                if (_fileStream != null)
                    throw new InvalidOperationException("файл уже открыт");

                _fileStream = new FileStream(_filePath, FileMode.OpenOrCreate, FileAccess.Write, FileShare.Read);
                _writer = new StreamWriter(_fileStream, Encoding.UTF8);
            }
            catch (Exception ex)
            {
                Dispose();
                throw new IOException($"ошибка при открытии файла для записи: {ex.Message}", ex);
            }
        }
    }

    public void OpenForReading()
    {
        ThrowIfDisposed();

        lock (_lockObject)
        {
            try
            {
                if (_fileStream != null)
                    throw new InvalidOperationException("файл уже открыт");

                if (!File.Exists(_filePath))
                    throw new FileNotFoundException("файл не найден", _filePath);

                _fileStream = new FileStream(_filePath, FileMode.Open, FileAccess.Read, FileShare.Read);
                _reader = new StreamReader(_fileStream, Encoding.UTF8);
            }
            catch (Exception ex)
            {
                Dispose();
                throw new IOException($"ошибка при открытии файла для чтения: {ex.Message}", ex);
            }
        }
    }

    public void WriteLine(string text)
    {
        ThrowIfDisposed();

        if (_writer == null)
            throw new InvalidOperationException("файл не открыт для записи");

        lock (_lockObject)
        {
            try
            {
                _writer.WriteLine(text);
                _writer.Flush();
            }
            catch (Exception ex)
            {
                throw new IOException($"ошибка при записи в файл: {ex.Message}", ex);
            }
        }
    }

    public string ReadAllText()
    {
        ThrowIfDisposed();

        if (_reader == null)
            throw new InvalidOperationException("файл не открыт для чтения");

        lock (_lockObject)
        {
            try
            {
                _reader.BaseStream.Position = 0;
                return _reader.ReadToEnd();
            }
            catch (Exception ex)
            {
                throw new IOException($"ошибка чтения из файла: {ex.Message}", ex);
            }
        }
    }

    public void AppendText(string text)
    {
        ThrowIfDisposed();

        if (_writer == null)
            throw new InvalidOperationException("файл не открыт для записи");

        lock (_lockObject)
        {
            try
            {
                _writer.Write(text);
                _writer.Flush();
            }
            catch (Exception ex)
            {
                throw new IOException($"ошибка добавления текста в файл: {ex.Message}", ex);
            }
        }
    }

    public FileInfo GetFileInfo()
    {
        ThrowIfDisposed();

        if (!File.Exists(_filePath))
            throw new FileNotFoundException("файл не найден", _filePath);

        return new FileInfo(_filePath);
    }

    private void ThrowIfDisposed()
    {
        if (_disposed)
            throw new ObjectDisposedException(nameof(FileResourceManager));
    }

    public void Dispose()
    {
        Dispose(true);
        GC.SuppressFinalize(this);
    }

    protected virtual void Dispose(bool disposing)
    {
        if (_disposed)
            return;

        if (disposing)
        {
            _writer?.Dispose();
            _reader?.Dispose();
            _fileStream?.Dispose();
            
            _writer = null;
            _reader = null;
            _fileStream = null;
        }

        _disposed = true;
    }

    ~FileResourceManager()
    {
        Dispose(false);
    }
}

