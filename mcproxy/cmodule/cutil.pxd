cdef void *alloc_object(size_t n) noexcept nogil


cdef void free_object(void *ptr, size_t n) noexcept nogil


cdef int bytes_equal(const char *a, int a_len, const char *b, int b_len) noexcept nogil


ctypedef void (*destroy_func)(void *obj) noexcept nogil


cdef struct RefCount:
    size_t count
    void *obj
    destroy_func destroy_fn


cdef void init_ref_count(RefCount *ref, void *obj, destroy_func destroy_fn) noexcept nogil


cdef void ref_inc(RefCount *ref) noexcept nogil


cdef void ref_dec(RefCount *ref) noexcept nogil
