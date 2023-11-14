from libc.stdlib cimport malloc, free


cdef unsigned int global_current_mem = 0


cdef void *alloc_object(size_t n) noexcept nogil:
    global global_current_mem
    global_current_mem += n
    return malloc(n)


cdef void free_object(void *ptr, size_t n) noexcept nogil:
    global global_current_mem
    global_current_mem -= n
    free(ptr)


def py_get_mem():
    global global_current_mem
    return global_current_mem


cdef int bytes_equal(const char *a, int a_len, const char *b, int b_len) noexcept nogil:
    cdef int i

    if a_len != b_len:
        return False

    for i in range(a_len):
        if a[i] != b[i]:
            return False
    return True
