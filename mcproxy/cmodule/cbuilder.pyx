from libc.string cimport memcpy

from cutil cimport alloc_object, free_object


DEF MAX_DATA = 4096


ctypedef int (*write_func)(void *obj, const char *data, int n) noexcept


cdef struct Builder:
    char buf[2 * MAX_DATA]
    int buf_len

    void *write_obj
    write_func write_fn


cdef struct MGetCmd:
    const char *key # non owning pointer
    int key_len
    int N


cdef Builder *make_builder(void *write_obj, write_func write_fn) noexcept nogil:
    cdef Builder *b = <Builder *>alloc_object(sizeof(Builder))

    b.buf_len = 0

    b.write_obj = write_obj
    b.write_fn = write_fn

    return b


cdef void free_builder(Builder *b) noexcept nogil:
    free_object(b, sizeof(Builder))


cdef void builder_append(Builder *b, const char *data, int n) noexcept nogil:
    cdef int index = b.buf_len
    memcpy(b.buf + index, data, n)
    b.buf_len += n


cdef int builder_add_mget(Builder *b, MGetCmd cmd) noexcept nogil:
    builder_append(b, 'mg ', 3)
    builder_append(b, cmd.key, cmd.key_len)
    builder_append(b, ' v\r\n', 4)
    return 0


cdef int builder_flush(Builder *b) noexcept:
    cdef int ret
    ret = b.write_fn(b.write_obj, b.buf, b.buf_len)
    b.buf_len = 0
    return ret


cdef int builder_finish(Builder *b) noexcept nogil:
    if b.buf_len > 0:
        with gil:
            return builder_flush(b)
    return 0


cdef int python_write_func(void *obj, const char *data, int n) noexcept:
    cdef object fn
    cdef bytes b

    fn = <object>obj
    b = data[:n]
    return fn(b)


cdef class BuilderTest:
    cdef Builder *b
    cdef object write_obj

    def __cinit__(self, object write_fn):
        self.write_obj = write_fn
        self.b = make_builder(<void *>write_fn, python_write_func)

    def __dealloc__(self):
        free_builder(self.b)
    
    def add_mget(self, bytes key):
        cdef const char *ptr = key
        cdef int key_len = len(key)

        cdef MGetCmd cmd = MGetCmd(key=ptr, key_len=key_len, N=0)
        return builder_add_mget(self.b, cmd)
    
    def finish(self):
        return builder_finish(self.b)
        
