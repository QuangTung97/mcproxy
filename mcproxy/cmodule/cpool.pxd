cdef class ObjectPool:
    cdef list objects
    cdef list free_indices
    cdef int size

    cpdef int put(self, object obj)

    cpdef void free(self, int index)
