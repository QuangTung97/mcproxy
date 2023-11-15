from libc.string cimport memcpy

from cutil cimport alloc_object, free_object
from cutil cimport RefCounter, SharedPtr, make_shared, ptr_free, ptr_get, ptr_clone
from cpool cimport ObjectPool
from cparser cimport Parser, new_parser, parser_free
from cbuilder cimport Builder, new_builder, builder_free


cdef ObjectPool client_pool = ObjectPool(1024)


def get_client_pool():
    return client_pool


cdef struct ClientPtr:
    SharedPtr __ptr


cdef ClientData client_ptr_get(ClientPtr *ptr) noexcept:
    return <ClientData>ptr_get(&ptr.__ptr)


cdef void client_ptr_destroy(void *obj) noexcept nogil:
    pass


cdef void client_ptr_free(void *obj) noexcept nogil:
    with gil:
        d = <ClientData>obj

        parser_free(d.parser)
        builder_free(d.builder)

        d.conn.close()
        client_pool.free(d.pool_index)


cdef int client_write_func(void *obj, const char *data, int n) noexcept:
    cdef ClientData client_data = <ClientData>obj
    cdef bytes b = data[:n]
    return client_data.conn.write(b)


cdef class ClientData:
    cdef object conn
    cdef RefCounter ref
    cdef int pool_index

    cdef Parser *parser
    cdef Builder *builder

    def __cinit__(self, object conn):
        self.conn = conn
        self.pool_index = client_pool.put(self)
        self.parser = new_parser()
        self.builder = new_builder(<void *>self, client_write_func, 4096)
    

    cdef void get_ptr(self, ClientPtr *ptr) noexcept nogil:
        make_shared(&ptr.__ptr, <void *>self, &self.ref, client_ptr_destroy, client_ptr_free)


cdef class Client:
    cdef ClientPtr ptr

    def __cinit__(self, object conn):
        cdef ClientData client_data = ClientData(conn)
        client_data.get_ptr(&self.ptr)
    
    cpdef Pipeline pipeline(self):
        cdef Pipeline p = Pipeline()
        ptr_clone(&p.ptr.__ptr, &self.ptr.__ptr)
        return p
    
    def __dealloc__(self):
        ptr_free(&self.ptr.__ptr)


cdef class Pipeline:
    cdef ClientPtr ptr

    def __dealloc__(self):
        ptr_free(&self.ptr.__ptr)
