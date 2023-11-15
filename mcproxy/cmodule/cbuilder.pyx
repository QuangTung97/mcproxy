from libc.string cimport memcpy, memmove

import cython

from cutil cimport alloc_object, free_object


DEF MAX_DATA = 4096


cdef struct Builder:
    char buf[2 * MAX_DATA]
    int buf_len
    int write_limit

    void *write_obj
    write_func write_fn

    const char *current_set_data
    int current_set_len


cdef Builder *new_builder(void *write_obj, write_func write_fn, int limit) noexcept nogil:
    cdef Builder *b = <Builder *>alloc_object(sizeof(Builder))

    b.buf_len = 0
    b.write_limit = limit

    b.write_obj = write_obj
    b.write_fn = write_fn

    return b


cdef void builder_free(Builder *b) noexcept nogil:
    free_object(b, sizeof(Builder))


cdef void builder_append(Builder *b, const char *data, int n) noexcept nogil:
    memcpy(b.buf + b.buf_len, data, n)
    b.buf_len += n


@cython.cdivision
cdef void builder_append_num(Builder *b, size_t num) noexcept nogil:
    cdef char buf[32]
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


cdef WriteStatus builder_internal_do_flush(Builder *b) noexcept nogil:
    cdef int n = builder_flush(b)
    if n == 0:
        return WriteStatus.WS_FULL
    
    # TODO Check Error

    memmove(b.buf, b.buf + n, b.buf_len - n)
    b.buf_len -= n
    return WriteStatus.WS_FLUSHED


cdef WriteStatus builder_write_if_full(Builder *b) noexcept nogil:
    if b.buf_len > b.write_limit:
        return builder_internal_do_flush(b)
    return WriteStatus.WS_NOOP


cdef WriteStatus builder_add_mget(Builder *b, MGetCmd cmd) noexcept nogil:
    builder_append(b, 'mg ', 3)
    builder_append(b, cmd.key, cmd.key_len)

    if cmd.N > 0:
        builder_append(b, ' N', 2)
        builder_append_num(b, cmd.N)

    builder_append(b, ' v\r\n', 4)

    return builder_write_if_full(b)


cdef WriteStatus builder_write_set_data(Builder *b) noexcept nogil:
    cdef int n
    cdef int remaining
    cdef int flushed
    cdef WriteStatus st = builder_write_if_full(b)

    while b.current_set_len > 0:
        n = b.current_set_len
        flushed = False

        remaining = b.write_limit - b.buf_len
        if n > remaining:
            flushed = True
            n = remaining
        
        builder_append(b, b.current_set_data, n)

        b.current_set_data += n
        b.current_set_len -= n

        if flushed:
            st = builder_internal_do_flush(b)
    
    builder_append(b, '\r\n', 2)
    
    return st


cdef WriteStatus builder_add_mset(Builder *b, MSetCmd cmd) noexcept nogil:
    builder_append(b, 'ms ', 3)
    builder_append(b, cmd.key, cmd.key_len)
    builder_append(b, ' ', 1)

    builder_append_num(b, cmd.data_len)
    
    if cmd.cas > 0:
        builder_append(b, ' C', 2)
        builder_append_num(b, cmd.cas)


    builder_append(b, '\r\n', 2)

    b.current_set_data = cmd.data
    b.current_set_len = cmd.data_len

    return builder_write_set_data(b)


cdef WriteStatus builder_add_mdel(Builder *b, MDelCmd cmd) noexcept nogil:
    builder_append(b, 'md ', 3)
    builder_append(b, cmd.key, cmd.key_len)
    builder_append(b, '\r\n', 2)
    return builder_write_if_full(b)


cdef int builder_flush(Builder *b) noexcept nogil:
    cdef int ret
    cdef int n = b.buf_len

    if n > b.write_limit:
        n = b.write_limit

    with gil:
        ret = b.write_fn(b.write_obj, b.buf, n)
    return ret


cdef WriteStatus builder_finish(Builder *b) noexcept nogil:
    if b.buf_len > 0:
        return builder_internal_do_flush(b)
    return WriteStatus.WS_NOOP


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
        self.b = new_builder(<void *>write_fn, python_write_func, limit)

    def __dealloc__(self):
        builder_free(self.b)
    
    def add_mget(self, bytes key, int N = 0):
        cdef const char *ptr = key
        cdef int key_len = len(key)

        cdef MGetCmd cmd = MGetCmd(key=ptr, key_len=key_len, N=N)
        return builder_add_mget(self.b, cmd)

    def add_mset(self, bytes key, bytes data, size_t cas = 0):
        cdef const char *ptr = key
        cdef int key_len = len(key)

        cdef const char *data_ptr = data
        cdef int data_len = len(data)

        cdef MSetCmd cmd = MSetCmd(key=ptr, key_len=key_len, data=data_ptr, data_len=data_len, cas=cas)
        return builder_add_mset(self.b, cmd)
    
    def add_delete(self, bytes key):
        cdef const char *ptr = key
        cdef int key_len = len(key)

        cdef MDelCmd cmd = MDelCmd(key=ptr, key_len=key_len)
        return builder_add_mdel(self.b, cmd)
    
    def finish(self):
        return builder_finish(self.b)
