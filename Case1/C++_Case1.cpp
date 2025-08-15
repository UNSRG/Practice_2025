#include <iostream>
#include <vector>
using namespace std;

int main() {
    int N;
    cout << "Введите размер массива N: ";
    cin >> N;

    vector<double> A(N);
    for (int i = 0; i < N; i++) {
        cout << "Введите элемент A[" << i << "]: ";
        cin >> A[i];
    }

    double B;
    cout << "Введите число B: ";
    cin >> B;

    double sum_pos = 0;
    int count_pos = 0;
    int count_greater = 0;
    double product_greater = 1;
    bool found_greater = false;

    for (double num : A) {
        if (num > 0) {
            sum_pos += num;
            count_pos++;
        }
        if (num > B) {
            count_greater++;
            product_greater *= num;
            found_greater = true;
        }
    }

    if (!found_greater) {
        product_greater = 0;
    }

    cout << "Сумма положительных элементов: " << sum_pos << endl;
    cout << "Количество положительных элементов: " << count_pos << endl;
    cout << "Количество элементов > " << B << ": " << count_greater << endl;
    cout << "Произведение элементов > " << B << ": " << product_greater << endl;

    return 0;
}