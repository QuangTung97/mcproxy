cdef void *alloc_object(size_t n) noexcept nogil


cdef void free_object(void *ptr, size_t n) noexcept nogil


cdef int bytes_equal(const char *a, int a_len, const char *b, int b_len) noexcept nogil


# ===================================
# Shared Pointer
# ===================================

ctypedef void (*destroy_func)(void *obj) noexcept nogil

ctypedef void (*free_func)(void *obj) noexcept nogil

cdef struct SharedPtr

cdef struct WeakPtr

cdef struct RefCounter:
    size_t count
    size_t weak_count
    destroy_func destroy_fn
    free_func free_fn

cdef void make_shared(SharedPtr *ptr, void *obj, RefCounter *ref, destroy_func destroy_fn, free_func free_fn) noexcept nogil

cdef void ptr_clone(SharedPtr *new_ptr, const SharedPtr *ptr) noexcept nogil

cdef void *ptr_get(const SharedPtr *ptr) noexcept nogil

cdef void ptr_free(SharedPtr *ptr) noexcept nogil

cdef void make_weak_ptr(WeakPtr *new_ptr, const SharedPtr *ptr) noexcept nogil

cdef void weak_ptr_clone(SharedPtr *new_ptr, const WeakPtr *ptr) noexcept nogil

cdef void weak_ptr_free(WeakPtr *ptr) noexcept nogil
