// Hàm hoán đổi 2 giá trị dùng con trỏ
void swap(int *a, int *b) {
    int temp = *a;
    *a = *b;
    *b = temp;
}

// Hàm sắp xếp nổi bọt
void bubble_sort(int arr[], int n) {
    int i, j;
    for (i = 0; i < n - 1; i++) {
        for (j = 0; j < n - i - 1; j++) {
            // Nếu phần tử trước lớn hơn phần tử sau -> Đảo vị trí
            if (arr[j] > arr[j + 1]) {
                swap(&arr[j], &arr[j + 1]);
            }
        }
    }
}
int my_array[10] = {42, 15, 77, 8, 23, 57, 86, 11, 43, 64};
int main() {
    // Gọi hàm sắp xếp mảng tăng dần
    bubble_sort(my_array, 10);
    return 0;
}