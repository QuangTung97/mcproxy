from libc.string cimport memcpy

from cutil cimport alloc_object, free_object
from cutil cimport bytes_equal


DEF TMP_DATA_MAX_LEN = 1024


cdef enum ParserState:
    P_INIT = 1
    P_HANDLE_V
    P_HANDLE_H
    P_HANDLE_N
    P_HANDLE_E
    P_FIND_CR

    P_MGET_VA
    P_MGET_VA_NUM
    P_MGET_VA_FLAGS
    P_MGET_VA_DATA

    P_VERSION
    P_VERSION_SPACE
    P_VERSION_VALUE

    P_HANDLE_CR
    P_HANDLE_LF


cdef struct Parser:
    ParserState state

    const char *data # non owning
    int data_len

    ParserCmd current
    ParserCmd next_cmd

    char tmp_data[TMP_DATA_MAX_LEN]
    int tmp_data_len

    char *response_data # owning
    int response_data_len
    int response_index

    int wait_response

    const char *last_error


cdef void parser_inc(Parser *p) noexcept nogil:
    p.data += 1
    p.data_len -= 1


cdef int parser_handle_init(Parser *p) noexcept nogil:
    cdef char ch = p.data[0]
    if ch == 'V':
        parser_inc(p)
        p.state = ParserState.P_HANDLE_V
        return 0

    elif ch == 'H':
        parser_inc(p)
        p.state = ParserState.P_HANDLE_H
        return 0
    
    elif ch == 'N':
        parser_inc(p)
        p.state = ParserState.P_HANDLE_N
        return 0

    elif ch == 'E':
        parser_inc(p)
        p.state = ParserState.P_HANDLE_E
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


cdef int parser_handle_h(Parser *p) noexcept nogil:
    if p.data[0] == 'D':
        parser_inc(p)
        p.state = ParserState.P_FIND_CR
        p.next_cmd = ParserCmd.P_CMD_HD
        return 0

    p.last_error = 'invalid character after H'
    return -1


cdef int parser_handle_n(Parser *p) noexcept nogil:
    cdef char ch = p.data[0]

    if ch == 'S':
        parser_inc(p)
        p.state = ParserState.P_FIND_CR
        p.next_cmd = ParserCmd.P_CMD_NS
        return 0
    elif ch == 'F':
        parser_inc(p)
        p.state = ParserState.P_FIND_CR
        p.next_cmd = ParserCmd.P_CMD_NF
        return 0

    p.last_error = 'invalid character after N'
    return -1


cdef int parser_handle_e(Parser *p) noexcept nogil:
    if p.data[0] == 'X':
        parser_inc(p)
        p.state = ParserState.P_FIND_CR
        p.next_cmd = ParserCmd.P_CMD_EX
        return 0

    p.last_error = 'invalid character after E'
    return -1


cdef int parser_handle_va_space(Parser *p) noexcept nogil:
    if is_space(p.data[0]):
        parser_inc(p)
        return 0
    
    p.state = ParserState.P_MGET_VA_NUM
    p.tmp_data_len = 0
    return 0


cdef int num_from_str(const char *s, int n) noexcept nogil:
    cdef int i
    cdef int res = 0
    cdef char zero  = '0'
    for i in range(n):
        res *= 10
        res += s[i] - zero
    return res


cdef void parser_free_response(Parser *p) noexcept nogil:
    if p.response_data != NULL:
        free_object(<void *>p.response_data, p.response_data_len)


cdef int parser_handle_va_num(Parser *p) noexcept nogil:
    cdef int ret
    cdef char ch = p.data[0]

    if is_digit(ch):
        ret =  parser_append_tmp(p, ch)
        parser_inc(p)
        return ret
    
    if ch != '\r' and not is_space(ch):
        p.last_error = 'not a VA number'
        return -1

    parser_free_response(p)
    
    p.state = ParserState.P_MGET_VA_FLAGS
    p.response_data_len = num_from_str(p.tmp_data, p.tmp_data_len)
    p.response_index = 0
    p.response_data = <char *>alloc_object(p.response_data_len)
    
    return 0

cdef int parser_handle_va_flags(Parser *p) noexcept nogil:
    if p.data[0] == '\r':
        p.state = ParserState.P_HANDLE_CR
        p.next_cmd = ParserCmd.P_CMD_MG
        p.wait_response = True
        return 0
    
    parser_inc(p)
    return 0


cdef int parser_handle_va_data(Parser *p) noexcept nogil:
    cdef int n = p.response_data_len - p.response_index

    if n > p.data_len:
        n = p.data_len
    else:
        p.state = ParserState.P_HANDLE_CR
        p.wait_response = False

    memcpy(<void *>p.response_data, <void *>p.data, n)

    p.data += n
    p.data_len -= n
    p.response_index += n

    return 0


cdef int parser_find_cr(Parser *p) noexcept nogil:
    if p.data[0] == '\r':
        p.state = ParserState.P_HANDLE_CR
        return 0

    parser_inc(p)
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

cdef int is_digit(char c) noexcept nogil:
    if c >= '0' and c <= '9':
        return True
    return False


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
    cdef int ret = parser_append_tmp(p, p.data[0])
    parser_inc(p)
    return ret


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

        if p.wait_response:
            p.state = ParserState.P_MGET_VA_DATA
            return 0

        p.current = p.next_cmd
        p.state = ParserState.P_INIT

        return 0
    
    p.last_error = 'invalid LF state'
    return -1


cdef int parser_handle_step(Parser *p) noexcept nogil:
    if p.state == ParserState.P_INIT:
        return parser_handle_init(p)
    elif p.state == ParserState.P_HANDLE_V:
        return parser_handle_v(p)
    elif p.state == ParserState.P_HANDLE_H:
        return parser_handle_h(p)
    elif p.state == ParserState.P_HANDLE_N:
        return parser_handle_n(p)
    elif p.state == ParserState.P_HANDLE_E:
        return parser_handle_e(p)
    elif p.state == ParserState.P_FIND_CR:
        return parser_find_cr(p)


    elif p.state == ParserState.P_MGET_VA:
        return parser_handle_va_space(p)
    elif p.state == ParserState.P_MGET_VA_NUM:
        return parser_handle_va_num(p)
    elif p.state == ParserState.P_MGET_VA_FLAGS:
        return parser_handle_va_flags(p)
    elif p.state == ParserState.P_MGET_VA_DATA:
        return parser_handle_va_data(p)


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

cdef int parser_handle_loop(Parser *p) noexcept nogil:
    cdef int ret = 0

    while p.data_len > 0 and p.current == ParserCmd.P_NO_CMD:
        ret = parser_handle_step(p)
        if ret:
            return ret

    return 0


cdef int parser_handle(Parser *p, const char *data, int n) noexcept nogil:
    p.data = data
    p.data_len = n

    return parser_handle_loop(p)


cdef ParserCmd parser_get_cmd(Parser *p, int *ret) noexcept nogil:
    ret[0] = parser_handle_loop(p)
    cdef ParserCmd cmd = p.current
    p.current = ParserCmd.P_NO_CMD
    return cmd


cdef bytes parser_get_string(Parser *p) noexcept:
    return p.tmp_data[:p.tmp_data_len]


cdef bytes parser_get_data(Parser *p) noexcept:
    cdef bytes b = p.response_data[:p.response_data_len]
    return b


cdef Parser *new_parser() noexcept nogil:
    cdef Parser *p = <Parser *>alloc_object(sizeof(Parser))

    p.state = ParserState.P_INIT

    p.data = NULL
    p.data_len = 0

    p.next_cmd = ParserCmd.P_NO_CMD
    p.current = ParserCmd.P_NO_CMD

    p.tmp_data_len = 0

    p.response_data = NULL
    p.response_data_len = 0
    p.response_index = 0

    p.wait_response = False

    p.last_error = NULL

    return p


cdef void parser_free(Parser *p) noexcept nogil:
    parser_free_response(p)
    free_object(<void *>p, sizeof(Parser))


cdef class ParserTest:
    cdef Parser *p

    def __cinit__(self):
        self.p = new_parser()

    def __dealloc__(self):
        if self.p != NULL:
            parser_free(self.p)


    def handle(self, bytes data):
        cdef int ret
        cdef str err_str

        cdef char *data_ptr = data
        cdef int data_len = len(data)

        with nogil:
            ret = parser_handle(self.p, data_ptr, data_len)
            if ret:
                with gil:
                    err_str = self.p.last_error.decode()
                    raise ValueError(err_str)
    
    def get(self):
        cdef int ret
        cdef ParserCmd cmd 

        with nogil:
            cmd = parser_get_cmd(self.p, &ret)
            if ret:
                with gil:
                    err_str = self.p.last_error.decode()
                    raise ValueError(err_str)
        return cmd
    
    def get_string(self):
        return parser_get_string(self.p)
    
    def get_len(self):
        return self.p.data_len
    
    def get_data(self):
        cdef Parser *p = self.p
        return parser_get_data(p)
