ОТЧЕТ О ПРОИЗВОДИТЕЛЬНОСТИ КОЛЛЕКЦИЙ

## List:

## Операция Среднее (мс) Мин (мс) Макс (мс)

AddToEnd 0 0 0  
AddToMiddle 0 0 0  
AddToStart 0 0 0  
FindByValue 26 25 33  
GetByIndex 0 0 0  
RemoveFromEnd 0 0 0  
RemoveFromMiddle 0 0 0  
RemoveFromStart 0 0 0

## LinkedList:

## Операция Среднее (мс) Мин (мс) Макс (мс)

AddToEnd 0 0 0  
AddToMiddle 0 0 1  
AddToStart 0 0 0  
FindByValue 301 260 358  
RemoveFromEnd 0 0 0  
RemoveFromMiddle 0 0 1  
RemoveFromStart 0 0 0

## Queue:

## Операция Среднее (мс) Мин (мс) Макс (мс)

AddToEnd 0 0 2  
FindByValue 27 25 36  
RemoveFromStart 0 0 0

## Stack:

## Операция Среднее (мс) Мин (мс) Макс (мс)

AddToEnd 0 0 0  
FindByValue 40 28 112  
RemoveFromEnd 0 0 0

## ImmutableList:

## Операция Среднее (мс) Мин (мс) Макс (мс)

AddToEnd 0 0 0  
AddToMiddle 0 0 3  
AddToStart 0 0 0  
FindByValue 654 615 796  
GetByIndex 0 0 1  
RemoveFromEnd 0 0 0  
RemoveFromMiddle 0 0 0  
RemoveFromStart 0 0 0

АНАЛИЗ И ВЫВОДЫ

AddToEnd:
Самый быстрый: List (0 мс)

AddToStart:
Самый быстрый: List (0 мс)

AddToMiddle:
Самый быстрый: List (0 мс)

RemoveFromStart:
Самый быстрый: List (0 мс)

RemoveFromEnd:
Самый быстрый: List (0 мс)

RemoveFromMiddle:
Самый быстрый: List (0 мс)

FindByValue:
Самый быстрый: List (26 мс)
Самый медленный: ImmutableList (654 мс)
Разница: 25,15x

GetByIndex:
Самый быстрый: List (0 мс)

ОБЩИЕ ВЫВОДЫ:

1. List<T> эффективен для добавления в конец и доступа по индексу.
2. LinkedList<T> эффективен для добавления/удаления в начале и конце.
3. Queue<T> оптимизирован для операций FIFO (добавление в конец, удаление из начала).
4. Stack<T> оптимизирован для операций LIFO (добавление и удаление с конца).
5. ImmutableList<T> создает новую коллекцию при каждой операции, что влияет на производительность.
6. Поиск в LinkedList медленнее из-за необходимости последовательного прохода.
7. Добавление в начало List требует сдвига всех элементов.
