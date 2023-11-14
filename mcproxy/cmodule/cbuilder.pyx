from libc.string cimport memcpy

import cython

from cutil cimport alloc_object, free_object


DEF MAX_DATA = 4096


ctypedef int (*write_func)(void *obj, const char *data, int n) noexcept


cdef struct Builder:
    char buf[2 * MAX_DATA]
    int buf_len
    int write_limit

    void *write_obj
    write_func write_fn


cdef struct MGetCmd:
    const char *key # non owning pointer
    int key_len
    int N


cdef Builder *make_builder(void *write_obj, write_func write_fn, int limit) noexcept nogil:
    cdef Builder *b = <Builder *>alloc_object(sizeof(Builder))

    b.buf_len = 0
    b.write_limit = limit

    b.write_obj = write_obj
    b.write_fn = write_fn

    return b


cdef void free_builder(Builder *b) noexcept nogil:
    free_object(b, sizeof(Builder))


cdef void builder_append(Builder *b, const char *data, int n) noexcept nogil:
    cdef int index = b.buf_len
    memcpy(b.buf + index, data, n)
    b.buf_len += n


@cython.cdivision
cdef void builder_append_num(Builder *b, int num) noexcept nogil:
    cdef char buf[16]
    cdef int num_len = 0
    cdef char zero = '0'
    cdef char ch
    cdef int i

    if num <= 0:
        builder_append(b, '0', 1)
        return

    while num > 0:
        ch = (num % 10) + zero
        buf[num_len] = ch
        num_len += 1

        num = num // 10
    
    for i in range(num_len // 2):
        buf[i], buf[num_len - 1 - i] = buf[num_len - 1 - i], buf[i]
    
    builder_append(b, buf, num_len)


cdef int builder_add_mget(Builder *b, MGetCmd cmd) noexcept nogil:
    cdef int ret

    builder_append(b, 'mg ', 3)
    builder_append(b, cmd.key, cmd.key_len)

    if cmd.N > 0:
        builder_append(b, ' N', 2)
        builder_append_num(b, cmd.N)

    builder_append(b, ' v\r\n', 4)

    if b.buf_len > b.write_limit:
        ret = builder_flush(b, b.write_limit)
        if ret:
            return ret
        memcpy(b.buf, b.buf + b.write_limit, b.buf_len)

    return 0


cdef int builder_flush(Builder *b, int n) noexcept nogil:
    cdef int ret
    with gil:
        ret = b.write_fn(b.write_obj, b.buf, n)
        b.buf_len -= n
    return ret


cdef int builder_finish(Builder *b) noexcept nogil:
    if b.buf_len > 0:
        return builder_flush(b, b.buf_len)
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

    def __cinit__(self, object write_fn, int limit):
        self.write_obj = write_fn
        self.b = make_builder(<void *>write_fn, python_write_func, limit)

    def __dealloc__(self):
        free_builder(self.b)
    
    def add_mget(self, bytes key, int N = 0):
        cdef const char *ptr = key
        cdef int key_len = len(key)

        cdef MGetCmd cmd = MGetCmd(key=ptr, key_len=key_len, N=N)
        return builder_add_mget(self.b, cmd)
    
    def finish(self):
        return builder_finish(self.b)
        
