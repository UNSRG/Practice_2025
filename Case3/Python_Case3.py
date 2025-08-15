import random

print("Генерация случайных чисел. Введите 0, чтобы остановить.")
numbers = []

while True:
    user_input = input("Введите число (0 — стоп): ")
    try:
        num = int(user_input)
        if num == 0:
            break
        numbers.append(random.randint(1, 100))
    except ValueError:
        print("Введите целое число!")

print("Сгенерированные числа (кроме последнего ввода):")
print(numbers)

# Задержка, чтобы окно не закрывалось
input("Нажмите Enter, чтобы выйти...")