cdef void *alloc_object(size_t n) noexcept nogil


cdef void free_object(void *ptr, size_t n) noexcept nogil


cdef int bytes_equal(const char *a, int a_len, const char *b, int b_len) noexcept nogil
