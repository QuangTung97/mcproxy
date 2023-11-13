from libc.string cimport memcpy
from cutil cimport alloc_object, free_object

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


cdef Conn *make_conn(int index) noexcept:
    cdef Conn *c = <Conn *>alloc_object(sizeof(Conn))
    c.index = index
    return c


cdef object get_conn(const Conn *c) noexcept:
    return global_conns[c.index]


cdef void free_conn(const Conn *c) noexcept:
    global global_conns
    global_conns[c.index] = None
    global_free_conns.append(c.index)
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
    return n


cdef int bytes_equal(const char *a, int a_len, const char *b, int b_len) noexcept:
    cdef int n
    cdef int i

    n = a_len
    if b_len < n:
        n = b_len

    for i in range(n):
        if a[i] != b[i]:
            return FALSE
    return TRUE

cdef bytes version_prefix = b'VERSION '
cdef int version_prefix_len = len(version_prefix)
cdef const char *version_c = version_prefix

cdef bytes conn_version(Conn *conn):
    cdef int n = conn_write(conn, 'version\r\n')
    n = conn_read(conn)
    if bytes_equal(conn.resp_data, MAX_DATA, version_c, version_prefix_len):
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


cdef enum PARSER_STATE:
    P_INIT = 1
    P_HANDLE_V

    P_MGET_VA

    P_VERSION
    P_VERSION_VALUE


cdef enum PARSER_CMD:
    P_NO_CMD = 0
    P_CMD_VERSION


DEF TMP_DATA_MAX_LEN = 1024


cdef struct Parser:
    PARSER_STATE state

    const char *data # non owning
    int data_len

    PARSER_CMD current

    char tmp_data[TMP_DATA_MAX_LEN]
    int tmp_data_len

    const char *last_error


cdef void parser_inc(Parser *p) noexcept:
    p.data += 1
    p.data_len -= 1


cdef int parser_handle_init(Parser *p) noexcept:
    if p.data[0] == 'V':
        parser_inc(p)
        p.state = P_HANDLE_V
        return 0

    return 0

cdef int parser_handle_v(Parser *p) noexcept:
    if p.data[0] == 'A':
        parser_inc(p)
        p.state = P_MGET_VA
        return 0

    if p.data[0] == 'E':
        parser_inc(p)
        p.state = P_VERSION
        return 0

    return 0


cdef int is_alphabet(char c) noexcept:
    if c >= 'A' and c <= 'Z':
        return 1
    if c >= 'a' and c <= 'z':
        return 1
    return 0


cdef int parser_append_tmp(Parser *p, char c) noexcept:
    if p.tmp_data_len >= TMP_DATA_MAX_LEN:
        p.last_error = 'response is too large'
        return -1
    p.tmp_data[p.tmp_data_len] = c
    p.tmp_data_len += 1
    return 0


cdef bytes version_suffix = b'RSION'
cdef int version_suffix_len = len(version_suffix)
cdef const char *version_suffix_c = version_suffix


cdef parser_handle_version(Parser *p):
    if is_alphabet(p.data[0]):
        parser_inc(p)
        return parser_append_tmp(p, p.data[0])
    
    if bytes_equal(p.tmp_data, p.tmp_data_len, version_suffix_c, version_suffix_len):
        p.state = P_VERSION_VALUE
        return 0
    
    return 0


cdef PARSER_CMD parser_get_cmd(Parser *p):
    return P_NO_CMD


cdef int parser_handle(Parser *p, const char *data, int n) noexcept:
    cdef int ret = 0

    p.data = data
    p.data_len = n

    while p.data_len > 0:
        if p.state == P_INIT:
            ret = parser_handle_init(p)
            if ret:
                return ret

            p.data_len = 0
            p.data = NULL
        elif p.state == P_HANDLE_V:
            ret = parser_handle_v(p)
            if ret:
                return ret
        elif p.state == P_VERSION:
            ret = parser_handle_version(p)
            if ret:
                return ret

    return 0


cdef class ParserTest:
    cdef Parser *p

    def __cinit__(self):
        cdef Parser *p = <Parser *>alloc_object(sizeof(Parser))

        p.state = P_INIT

        p.data = NULL
        p.data_len = 0

        p.current = P_NO_CMD

        p.tmp_data_len = 0

        p.last_error = NULL

        self.p = p

    def __dealloc__(self):
        free_object(self.p, sizeof(Parser))

    def handle(self, bytes data):
        parser_handle(self.p, data, len(data))
    
    def get(self):
        return parser_get_cmd(self.p)