from libc.string cimport memcpy

from cutil cimport alloc_object, free_object
from cutil cimport bytes_equal


cdef list global_conns = list() # list of connections
cdef list global_free_conns = list() # list of indices

def get_global_conns():
    return global_conns

def get_global_free_conns():
    return global_free_conns


DEF MAX_DATA = 4096


cdef struct Conn:
    void *conn_ptr
    int index
    char resp_data[MAX_DATA]
    int resp_len


cdef Conn *make_conn(int index, void *conn_ptr) noexcept:
    cdef Conn *c = <Conn *>alloc_object(sizeof(Conn))
    c.index = index
    c.conn_ptr = conn_ptr
    c.resp_len = 0
    return c


cdef object get_conn(const Conn *c) noexcept:
    return <object>c.conn_ptr


cdef void free_conn(Conn *c) noexcept:
    global_conns[c.index] = None
    global_free_conns.append(c.index)

    c.conn_ptr = NULL

    free_object(<void *>c, sizeof(Conn))


cdef int conn_write(Conn *conn, const char *data):
    cdef bytes b = data
    cdef object c = get_conn(conn)
    return c.send(b)


cdef int conn_read(Conn *conn):
    cdef object c = get_conn(conn)
    d = c.recv(MAX_DATA)
    cdef const char *data = d
    cdef int n = len(d)
    memcpy(conn.resp_data, data, n)
    conn.resp_len += n
    return n



cdef bytes version_prefix = b'VERSION '
cdef int version_prefix_len = len(version_prefix)
cdef const char *version_c = version_prefix

cdef bytes conn_version(Conn *conn):
    cdef int n = conn_write(conn, 'version\r\n')
    n = conn_read(conn)
    if n > version_prefix_len:
        if bytes_equal(conn.resp_data, version_prefix_len, version_c, version_prefix_len):
            return conn.resp_data[version_prefix_len:n - 2]


cdef class Client:
    cdef Conn *conn

    def __cinit__(self, object new_conn):
        cdef object conn = new_conn()

        cdef int index

        if len(global_free_conns) > 0:
            index = global_free_conns.pop()
            global_conns[index] = conn
        else:
            index = len(global_conns)
            global_conns.append(conn)

        self.conn = make_conn(index, <void *>conn)

    def __dealloc__(self):
        if self.conn:
            c = get_conn(self.conn)
            free_conn(self.conn)
            c.close()

    cpdef str version(self):
        return conn_version(self.conn).decode()
