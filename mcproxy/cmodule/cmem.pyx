from libc.string cimport memcpy

from cutil cimport alloc_object, free_object
from cutil cimport RefCounter, SharedPtr, make_shared, ptr_free, ptr_get, ptr_clone
from cpool cimport ObjectPool


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
        d.conn.close()
        client_pool.free(d.pool_index)


cdef class ClientData:
    cdef object conn
    cdef RefCounter ref
    cdef int pool_index

    def __cinit__(self, object conn):
        self.conn = conn
        self.pool_index = client_pool.put(self)
    

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
