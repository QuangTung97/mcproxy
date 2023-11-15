cdef struct Builder

ctypedef int (*write_func)(void *obj, const char *data, int n) noexcept

cdef Builder *make_builder(void *write_obj, write_func write_fn, int limit) noexcept nogil


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


cdef int builder_add_mget(Builder *b, MGetCmd cmd) noexcept nogil

cdef int builder_add_mset(Builder *b, MSetCmd cmd) noexcept nogil

cdef int builder_add_mdel(Builder *b, MDelCmd cmd) noexcept nogil

cdef int builder_finish(Builder *b) noexcept nogil

cdef void builder_free(Builder *b) noexcept nogil