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


cdef void init_ref_count(RefCount *ref, void *obj, destroy_func destroy_fn) noexcept nogil:
    ref.count = 1
    ref.obj = obj
    ref.destroy_fn = destroy_fn


cdef void ref_inc(RefCount *ref) noexcept nogil:
    if ref.count == 0:
        with gil:
            print('[ERROR] invalid ref count increase')
        return

    ref.count += 1


cdef void ref_dec(RefCount *ref) noexcept nogil:
    if ref.count == 0:
        with gil:
            print('[ERROR] invalid ref count decrease')
        return

    ref.count -= 1
    if ref.count == 0:
        ref.destroy_fn(ref.obj)
