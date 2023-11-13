cdef void *alloc_object(size_t n) noexcept

cdef void free_object(void *ptr, size_t n) noexcept

cdef size_t get_current_mem() noexcept