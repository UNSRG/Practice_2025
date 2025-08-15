# Ввод данных
N = int(input("Введите размер массива N: "))
A = []
for i in range(N):
    A.append(float(input(f"Введите элемент A[{i}]: ")))

B = float(input("Введите число B: "))

# Инициализация переменных
sum_pos = 0
count_pos = 0
count_greater = 0
product_greater = 1
found_greater = False  # флаг для проверки наличия элементов > B

# Обработка массива
for num in A:
    if num > 0:
        sum_pos += num
        count_pos += 1
    if num > B:
        count_greater += 1
        product_greater *= num
        found_greater = True

# Если нет элементов > B, произведение = 0 (по аналогии с суммой)
if not found_greater:
    product_greater = 0

# Вывод результатов
print(f"Сумма положительных элементов: {sum_pos}")
print(f"Количество положительных элементов: {count_pos}")
print(f"Количество элементов > {B}: {count_greater}")
print(f"Произведение элементов > {B}: {product_greater}")