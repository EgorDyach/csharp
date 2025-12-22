using System.Collections;

namespace lab3.Collections;

public class SimpleDictionary<TKey, TValue> : IDictionary<TKey, TValue>, IReadOnlyDictionary<TKey, TValue>
    where TKey : notnull
{
    private struct Entry
    {
        public int HashCode;
        public int Next;
        public TKey Key;
        public TValue Value;
    }

    private int[] _buckets;
    private Entry[] _entries;
    private int _count;
    private int _freeList;
    private int _freeCount;
    private const int DefaultCapacity = 4;

    public SimpleDictionary()
    {
        _buckets = new int[DefaultCapacity];
        _entries = new Entry[DefaultCapacity];
        _count = 0;
        _freeList = -1;
        _freeCount = 0;

        for (int i = 0; i < _buckets.Length; i++)
        {
            _buckets[i] = -1;
        }
    }

    public TValue this[TKey key]
    {
        get
        {
            if (TryGetValue(key, out TValue? value))
                return value;
            throw new KeyNotFoundException($"ключ '{key}' не найден");
        }
        set
        {
            Insert(key, value, false);
        }
    }

    public ICollection<TKey> Keys
    {
        get
        {
            var keys = new List<TKey>();
            for (int i = 0; i < _count; i++)
            {
                if (_entries[i].HashCode >= 0)
                {
                    keys.Add(_entries[i].Key);
                }
            }
            return keys;
        }
    }

    public ICollection<TValue> Values
    {
        get
        {
            var values = new List<TValue>();
            for (int i = 0; i < _count; i++)
            {
                if (_entries[i].HashCode >= 0)
                {
                    values.Add(_entries[i].Value);
                }
            }
            return values;
        }
    }

    IEnumerable<TKey> IReadOnlyDictionary<TKey, TValue>.Keys => Keys;

    IEnumerable<TValue> IReadOnlyDictionary<TKey, TValue>.Values => Values;

    public int Count => _count - _freeCount;

    public bool IsReadOnly => false;

    public void Add(TKey key, TValue value)
    {
        if (!Insert(key, value, true))
            throw new ArgumentException($"элемент с ключом '{key}' уже существует");
    }

    public void Add(KeyValuePair<TKey, TValue> item)
    {
        Add(item.Key, item.Value);
    }

    public void Clear()
    {
        if (_count > 0)
        {
            for (int i = 0; i < _buckets.Length; i++)
            {
                _buckets[i] = -1;
            }
            Array.Clear(_entries, 0, _count);
            _freeList = -1;
            _count = 0;
            _freeCount = 0;
        }
    }

    public bool Contains(KeyValuePair<TKey, TValue> item)
    {
        if (TryGetValue(item.Key, out TValue? value))
            return EqualityComparer<TValue>.Default.Equals(value, item.Value);
        return false;
    }

    public bool ContainsKey(TKey key)
    {
        return TryGetValue(key, out _);
    }

    public void CopyTo(KeyValuePair<TKey, TValue>[] array, int arrayIndex)
    {
        if (array == null)
            throw new ArgumentNullException(nameof(array));
        if (arrayIndex < 0)
            throw new ArgumentOutOfRangeException(nameof(arrayIndex), "индекс не может быть отрицательным");
        if (array.Length - arrayIndex < Count)
            throw new ArgumentException("недостаточно места в массиве");

        int index = arrayIndex;
        foreach (var entry in this)
        {
            array[index++] = entry;
        }
    }

    public IEnumerator<KeyValuePair<TKey, TValue>> GetEnumerator()
    {
        for (int i = 0; i < _count; i++)
        {
            if (_entries[i].HashCode >= 0)
            {
                yield return new KeyValuePair<TKey, TValue>(_entries[i].Key, _entries[i].Value);
            }
        }
    }

    IEnumerator IEnumerable.GetEnumerator()
    {
        return GetEnumerator();
    }

    public bool Remove(TKey key)
    {
        if (key == null)
            throw new ArgumentNullException(nameof(key));

        int hashCode = key.GetHashCode() & 0x7FFFFFFF;
        int bucket = hashCode % _buckets.Length;
        int last = -1;

        for (int i = _buckets[bucket]; i >= 0; last = i, i = _entries[i].Next)
        {
            if (_entries[i].HashCode == hashCode && EqualityComparer<TKey>.Default.Equals(_entries[i].Key, key))
            {
                if (last < 0)
                {
                    _buckets[bucket] = _entries[i].Next;
                }
                else
                {
                    _entries[last].Next = _entries[i].Next;
                }

                _entries[i].HashCode = -1;
                _entries[i].Next = _freeList;
                _entries[i].Key = default(TKey)!;
                _entries[i].Value = default(TValue)!;
                _freeList = i;
                _freeCount++;
                return true;
            }
        }

        return false;
    }

    public bool Remove(KeyValuePair<TKey, TValue> item)
    {
        if (Contains(item))
        {
            return Remove(item.Key);
        }
        return false;
    }

    public bool TryGetValue(TKey key, out TValue value)
    {
        if (key == null)
            throw new ArgumentNullException(nameof(key));

        int hashCode = key.GetHashCode() & 0x7FFFFFFF;
        int bucket = hashCode % _buckets.Length;

        for (int i = _buckets[bucket]; i >= 0; i = _entries[i].Next)
        {
            if (_entries[i].HashCode == hashCode && EqualityComparer<TKey>.Default.Equals(_entries[i].Key, key))
            {
                value = _entries[i].Value;
                return true;
            }
        }

        value = default(TValue)!;
        return false;
    }

    private bool Insert(TKey key, TValue value, bool add)
    {
        if (key == null)
            throw new ArgumentNullException(nameof(key));

        int hashCode = key.GetHashCode() & 0x7FFFFFFF;
        int targetBucket = hashCode % _buckets.Length;

        for (int i = _buckets[targetBucket]; i >= 0; i = _entries[i].Next)
        {
            if (_entries[i].HashCode == hashCode && EqualityComparer<TKey>.Default.Equals(_entries[i].Key, key))
            {
                if (add)
                    return false;

                _entries[i].Value = value;
                return true;
            }
        }

        int index;
        if (_freeCount > 0)
        {
            index = _freeList;
            _freeList = _entries[index].Next;
            _freeCount--;
        }
        else
        {
            if (_count == _entries.Length)
            {
                Resize();
                targetBucket = hashCode % _buckets.Length;
            }
            index = _count;
            _count++;
        }

        _entries[index].HashCode = hashCode;
        _entries[index].Next = _buckets[targetBucket];
        _entries[index].Key = key;
        _entries[index].Value = value;
        _buckets[targetBucket] = index;

        return true;
    }

    private void Resize()
    {
        int newSize = _buckets.Length * 2;
        int[] newBuckets = new int[newSize];
        Entry[] newEntries = new Entry[newSize];

        for (int i = 0; i < newBuckets.Length; i++)
        {
            newBuckets[i] = -1;
        }

        Array.Copy(_entries, 0, newEntries, 0, _count);

        for (int i = 0; i < _count; i++)
        {
            if (newEntries[i].HashCode >= 0)
            {
                int bucket = newEntries[i].HashCode % newSize;
                newEntries[i].Next = newBuckets[bucket];
                newBuckets[bucket] = i;
            }
        }

        _buckets = newBuckets;
        _entries = newEntries;
    }
}

