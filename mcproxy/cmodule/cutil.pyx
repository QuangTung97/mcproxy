from libc.stdlib cimport malloc, free


cdef unsigned int global_current_mem = 0

cdef void *alloc_object(size_t n) noexcept:
    global global_current_mem
    global_current_mem += n
    return malloc(n)

cdef void free_object(void *ptr, size_t n) noexcept:
    global global_current_mem
    global_current_mem -= n
    free(ptr)

cdef size_t get_current_mem() noexcept:
    global global_current_mem
    return global_current_mem

def py_get_mem():
    return get_current_mem()