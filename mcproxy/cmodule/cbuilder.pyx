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


cdef struct MSetCmd:
    const char *key # non owning pointer
    int key_len

    const char *data # non owning pointer
    int data_len

    size_t cas


cdef struct MDelCmd:
    const char *key # non owning pointer
    int key_len


cdef Builder *make_builder(void *write_obj, write_func write_fn, int limit) noexcept nogil:
    cdef Builder *b = <Builder *>alloc_object(sizeof(Builder))

    b.buf_len = 0
    b.write_limit = limit

    b.write_obj = write_obj
    b.write_fn = write_fn

    return b


cdef void free_builder(Builder *b) noexcept nogil:
    free_object(b, sizeof(Builder))


cdef int builder_append(Builder *b, const char *data, int n) noexcept nogil:
    cdef int data_size
    cdef int reset
    cdef int remaining

    while n > 0:
        reset = False
        data_size = n
        remaining = b.write_limit - b.buf_len

        if data_size > remaining:
            reset = True
            data_size = remaining

        memcpy(b.buf + b.buf_len, data, data_size)

        data += data_size
        n -= data_size
        b.buf_len += data_size

        if reset:
            ret = builder_flush(b)
            if ret:
                return ret

    return 0


@cython.cdivision
cdef int builder_append_num(Builder *b, size_t num) noexcept nogil:
    cdef char buf[32]
    cdef int num_len = 0
    cdef char zero = '0'
    cdef char ch
    cdef int i

    if num <= 0:
        return builder_append(b, '0', 1)

    while num > 0:
        ch = (num % 10) + zero
        buf[num_len] = ch
        num_len += 1

        num = num // 10
    
    for i in range(num_len // 2):
        buf[i], buf[num_len - 1 - i] = buf[num_len - 1 - i], buf[i]
    
    return builder_append(b, buf, num_len)


cdef int builder_add_mget(Builder *b, MGetCmd cmd) noexcept nogil:
    cdef int ret

    ret = builder_append(b, 'mg ', 3)
    if ret:
        return ret

    ret = builder_append(b, cmd.key, cmd.key_len)
    if ret:
        return ret

    if cmd.N > 0:
        ret = builder_append(b, ' N', 2)
        if ret:
            return ret

        ret = builder_append_num(b, cmd.N)
        if ret:
            return ret

    ret = builder_append(b, ' v\r\n', 4)
    if ret:
        return ret

    return 0


cdef int builder_add_mset(Builder *b, MSetCmd cmd) noexcept nogil:
    cdef int ret
    ret = builder_append(b, 'ms ', 3)
    if ret:
        return ret
    
    ret = builder_append(b, cmd.key, cmd.key_len)
    if ret:
        return ret

    ret = builder_append(b, ' ', 1)
    if ret:
        return ret

    ret = builder_append_num(b, cmd.data_len)
    if ret:
        return ret
    
    if cmd.cas > 0:
        ret = builder_append(b, ' C', 2)
        if ret:
            return ret

        ret = builder_append_num(b, cmd.cas)
        if ret:
            return ret


    ret = builder_append(b, '\r\n', 2)
    if ret:
        return ret

    ret = builder_append(b, cmd.data, cmd.data_len)
    if ret:
        return ret

    ret = builder_append(b, '\r\n', 2)
    if ret:
        return ret

    return 0


cdef int builder_add_mdel(Builder *b, MDelCmd cmd) noexcept nogil:
    cdef int ret

    ret = builder_append(b, 'md ', 3)
    if ret:
        return ret

    ret = builder_append(b, cmd.key, cmd.key_len)
    if ret:
        return ret

    ret = builder_append(b, '\r\n', 2)
    if ret:
        return ret
    
    return 0


cdef int builder_flush(Builder *b) noexcept nogil:
    cdef int ret
    with gil:
        ret = b.write_fn(b.write_obj, b.buf, b.buf_len)
        b.buf_len = 0
    return ret


cdef int builder_finish(Builder *b) noexcept nogil:
    if b.buf_len > 0:
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
        
