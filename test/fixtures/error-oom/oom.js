const data = [];
while (true) {
    data.push(
        // Allocate 2GiB-1 repeatedly until out of memory
        new Array(2 ** 31 - 1).fill('a')
    );
}
