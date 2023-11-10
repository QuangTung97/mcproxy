from libc.stdlib cimport malloc, free
from libc.string cimport memcpy

cdef list global_conns = list() # list of connections
cdef list global_free_conns = list() # list of indices

def get_global_conns():
    return global_conns

def get_global_free_conns():
    return global_free_conns

DEF MAX_DATA = 4096
DEF TRUE = 1
DEF FALSE = 0


cdef struct Conn:
    int index
    char resp_data[MAX_DATA]


cdef Conn *make_conn(int index):
    cdef Conn *c = <Conn *>malloc(sizeof(Conn))
    c.index = index
    return c


cdef object get_conn(const Conn *c):
    return global_conns[c.index]


cdef void free_conn(const Conn *c):
    global global_conns
    global_conns[c.index] = None
    global_free_conns.append(c.index)
    free(<void *>c)


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
    return n


cdef int bytes_equal(const char *a, const char *b, int length):
    cdef int i
    for i in range(length):
        if a[i] != b[i]:
            return FALSE
    return TRUE

cdef bytes version_prefix = b'VERSION '
cdef int version_prefix_len = len(version_prefix)
cdef const char *version_c = version_prefix

cdef bytes conn_version(Conn *conn):
    cdef int n = conn_write(conn, 'version\r\n')
    n = conn_read(conn)
    if bytes_equal(conn.resp_data, version_c, version_prefix_len):
        return conn.resp_data[version_prefix_len:n - 2]


cdef class Client:
    cdef Conn *conn

    def __cinit__(self, object new_conn):
        conn = new_conn()

        cdef int index

        if len(global_free_conns) > 0:
            index = global_free_conns.pop()
            global_conns[index] = conn
        else:
            index = len(global_conns)
            global_conns.append(conn)

        self.conn = make_conn(index)

    def __dealloc__(self):
        if self.conn:
            c = get_conn(self.conn)
            free_conn(self.conn)
            c.close()

    cpdef str version(self):
        return conn_version(self.conn).decode()