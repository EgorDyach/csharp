using lab3.Collections;

namespace lab3;

class Program
{
    static void Main(string[] args)
    {
        Console.WriteLine("тестирование SimpleList:");
        var list = new SimpleList<int>();
        list.Add(1);
        list.Add(2);
        list.Add(3);
        Console.WriteLine($"количество элементов: {list.Count}");
        foreach (var item in list)
        {
            Console.WriteLine(item);
        }

        Console.WriteLine("\nтестирование SimpleDictionary:");
        var dict = new SimpleDictionary<string, int>();
        dict.Add("один", 1);
        dict.Add("два", 2);
        dict.Add("три", 3);
        Console.WriteLine($"количество элементов: {dict.Count}");
        foreach (var kvp in dict)
        {
            Console.WriteLine($"{kvp.Key}: {kvp.Value}");
        }

        Console.WriteLine("\nтестирование DoublyLinkedList:");
        var linkedList = new DoublyLinkedList<int>();
        linkedList.Add(10);
        linkedList.Add(20);
        linkedList.Add(30);
        Console.WriteLine($"количество элементов: {linkedList.Count}");
        foreach (var item in linkedList)
        {
            Console.WriteLine(item);
        }
    }
}

