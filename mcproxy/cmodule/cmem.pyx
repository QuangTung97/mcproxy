from libc.string cimport memcpy

from cutil cimport alloc_object, free_object


cdef list global_conns = list() # list of connections
cdef list global_free_conns = list() # list of indices

def get_global_conns():
    return global_conns

def get_global_free_conns():
    return global_free_conns


DEF MAX_DATA = 4096
DEF TMP_DATA_MAX_LEN = 1024


cdef struct Conn:
    int index
    char resp_data[MAX_DATA]
    int resp_len


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
    conn.resp_len += n
    return n


cdef int bytes_equal(const char *a, int a_len, const char *b, int b_len) noexcept nogil:
    cdef int i

    if a_len != b_len:
        return False

    for i in range(a_len):
        if a[i] != b[i]:
            return False
    return True

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


cdef enum ParserState:
    P_INIT = 1
    P_HANDLE_V

    P_MGET_VA

    P_VERSION
    P_VERSION_SPACE
    P_VERSION_VALUE

    P_HANDLE_CR
    P_HANDLE_LF


cdef enum ParserCmd:
    P_NO_CMD = 0
    P_CMD_VERSION



cdef struct Parser:
    ParserState state

    const char *data # non owning
    int data_len

    ParserCmd current
    ParserCmd next_cmd

    char tmp_data[TMP_DATA_MAX_LEN]
    int tmp_data_len

    const char *last_error


cdef void parser_inc(Parser *p) noexcept nogil:
    p.data += 1
    p.data_len -= 1


cdef int parser_handle_init(Parser *p) noexcept nogil:
    if p.data[0] == 'V':
        parser_inc(p)
        p.state = ParserState.P_HANDLE_V
        return 0

    p.last_error = 'invalid response'
    return -1

cdef int parser_handle_v(Parser *p) noexcept nogil:
    if p.data[0] == 'A':
        parser_inc(p)
        p.state = ParserState.P_MGET_VA
        return 0

    if p.data[0] == 'E':
        parser_inc(p)
        p.state = ParserState.P_VERSION
        p.tmp_data_len = 0
        return 0

    return 0


cdef int is_alphabet(char c) noexcept nogil:
    if c >= 'A' and c <= 'Z':
        return 1
    if c >= 'a' and c <= 'z':
        return 1
    return 0

cdef int is_space(char c) noexcept nogil:
    if c == ' ':
        return 1
    if c == '\t':
        return 1
    return 0


cdef int parser_append_tmp(Parser *p, char c) noexcept nogil:
    if p.tmp_data_len >= TMP_DATA_MAX_LEN:
        p.last_error = 'response is too large'
        return -1
    p.tmp_data[p.tmp_data_len] = c
    p.tmp_data_len += 1
    return 0


cdef bytes version_suffix = b'RSION'
cdef int version_suffix_len = len(version_suffix)
cdef const char *version_suffix_c = version_suffix


cdef int parser_handle_version(Parser *p) noexcept nogil:
    cdef int ret

    if is_alphabet(p.data[0]):
        ret = parser_append_tmp(p, p.data[0])
        parser_inc(p)
        return ret
    
    if bytes_equal(p.tmp_data, p.tmp_data_len, version_suffix_c, version_suffix_len):
        p.state = ParserState.P_VERSION_SPACE
        return 0
    
    p.last_error = 'invalid VERSION string'
    return -1


cdef int parser_handle_version_space(Parser *p) noexcept nogil:
    if is_space(p.data[0]):
        parser_inc(p)
        return 0

    p.tmp_data_len = 0
    p.state = ParserState.P_VERSION_VALUE
    return 0


cdef int parser_handle_version_value(Parser *p) noexcept nogil:
    if p.data[0] == '\r':
        p.state = ParserState.P_HANDLE_CR
        p.next_cmd = ParserCmd.P_CMD_VERSION
        return 0
    parser_append_tmp(p, p.data[0])
    parser_inc(p)
    return 0


cdef int parser_handle_cr(Parser *p) noexcept nogil:
    if p.data[0] == '\r':
        parser_inc(p)
        p.state = ParserState.P_HANDLE_LF
        return 0
    
    p.last_error = 'invalid CR state'
    return -1


cdef int parser_handle_lf(Parser *p) noexcept nogil:
    if p.data[0] == '\n':
        parser_inc(p)
        p.current = p.next_cmd
        p.state = ParserState.P_INIT
        return 0
    
    p.last_error = 'invalid LF state'
    return -1


cdef ParserCmd parser_get_cmd(Parser *p):
    return p.current


cdef int parser_handle_step(Parser *p) noexcept nogil:
    if p.state == ParserState.P_INIT:
        return parser_handle_init(p)
    elif p.state == ParserState.P_HANDLE_V:
        return parser_handle_v(p)
    elif p.state == ParserState.P_VERSION:
        return parser_handle_version(p)
    elif p.state == ParserState.P_VERSION_SPACE:
        return parser_handle_version_space(p)
    elif p.state == ParserState.P_VERSION_VALUE:
        return parser_handle_version_value(p)
    elif p.state == ParserState.P_HANDLE_CR:
        return parser_handle_cr(p)
    elif p.state == ParserState.P_HANDLE_LF:
        return parser_handle_lf(p)
    
    p.last_error = 'invalid parser state'
    return -1



cdef int parser_handle(Parser *p, const char *data, int n) noexcept nogil:
    cdef int ret = 0

    p.data = data
    p.data_len = n

    while p.data_len > 0 and p.current == ParserCmd.P_NO_CMD:
        ret = parser_handle_step(p)
        if ret:
            return ret

    return 0


cdef bytes parser_get_string(Parser *p) noexcept:
    return p.tmp_data[:p.tmp_data_len]


cdef class ParserTest:
    cdef Parser *p

    def __cinit__(self):
        cdef Parser *p = <Parser *>alloc_object(sizeof(Parser))

        p.state = ParserState.P_INIT

        p.data = NULL
        p.data_len = 0

        p.next_cmd = ParserCmd.P_NO_CMD
        p.current = ParserCmd.P_NO_CMD

        p.tmp_data_len = 0

        p.last_error = NULL

        self.p = p

    def __dealloc__(self):
        free_object(self.p, sizeof(Parser))

    def handle(self, bytes data):
        cdef int ret
        cdef str err_str
        ret = parser_handle(self.p, data, len(data))
        if ret:
            err_str = self.p.last_error.decode()
            raise ValueError(err_str)
    
    def get(self):
        return parser_get_cmd(self.p)
    
    def get_string(self):
        return parser_get_string(self.p)
    
    def get_len(self):
        return self.p.data_len