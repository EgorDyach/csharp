using System.Collections;

namespace lab3.Collections;

public class SimpleList<T> : IList<T>, ICollection<T>, IEnumerable<T>
{
    private T[] _items;
    private int _count;
    private const int DefaultCapacity = 4;

    public SimpleList()
    {
        _items = new T[DefaultCapacity];
        _count = 0;
    }

    public SimpleList(int capacity)
    {
        if (capacity < 0)
            throw new Exception("емкость не может быть отрицательной");
        _items = new T[capacity];
        _count = 0;
    }

    public T this[int index]
    {
        get
        {
            if (index < 0 || index >= _count)
                throw new Exception("индекс вне диапазона");
            return _items[index];
        }
        set
        {
            if (index < 0 || index >= _count)
                throw new Exception("индекс вне диапазона");
            _items[index] = value;
        }
    }

    public int Count => _count;

    public bool IsReadOnly => false;

    public void Add(T item)
    {
        if (_count >= _items.Length)
        {
            Grow();
        }
        _items[_count] = item;
        _count++;
    }

    public void Clear()
    {
        Array.Clear(_items, 0, _count);
        _count = 0;
    }

    public bool Contains(T item)
    {
        return IndexOf(item) >= 0;
    }

    public void CopyTo(T[] array, int arrayIndex)
    {
        if (array == null)
            throw new Exception("массив не может быть null");
        if (arrayIndex < 0)
            throw new Exception("индекс не может быть отрицательным");
        if (array.Length - arrayIndex < _count)
            throw new Exception("недостаточно места в массиве");

        Array.Copy(_items, 0, array, arrayIndex, _count);
    }

    public IEnumerator<T> GetEnumerator()
    {
        for (int i = 0; i < _count; i++)
        {
            yield return _items[i];
        }
    }

    IEnumerator IEnumerable.GetEnumerator()
    {
        return GetEnumerator();
    }

    public int IndexOf(T item)
    {
        for (int i = 0; i < _count; i++)
        {
            if (EqualityComparer<T>.Default.Equals(_items[i], item))
                return i;
        }
        return -1;
    }

    public void Insert(int index, T item)
    {
        if (index < 0 || index > _count)
            throw new Exception("индекс вне диапазона");

        if (_count >= _items.Length)
        {
            Grow();
        }

        if (index < _count)
        {
            Array.Copy(_items, index, _items, index + 1, _count - index);
        }

        _items[index] = item;
        _count++;
    }

    public bool Remove(T item)
    {
        int index = IndexOf(item);
        if (index >= 0)
        {
            RemoveAt(index);
            return true;
        }
        return false;
    }

    public void RemoveAt(int index)
    {
        if (index < 0 || index >= _count)
            throw new Exception("индекс вне диапазона");

        _count--;
        if (index < _count)
        {
            Array.Copy(_items, index + 1, _items, index, _count - index);
        }
        _items[_count] = default(T)!;
    }

    private void Grow()
    {
        int newCapacity = _items.Length == 0 ? DefaultCapacity : _items.Length * 2;
        T[] newItems = new T[newCapacity];
        Array.Copy(_items, newItems, _count);
        _items = newItems;
    }
}

