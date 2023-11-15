cdef struct Parser

cdef Parser *new_parser() noexcept nogil

cdef void parser_free(Parser *p) noexcept nogil

cdef int parser_handle(Parser *p, const char *data, int n) noexcept nogil

cdef enum ParserCmd:
    P_NO_CMD = 0
    P_CMD_VERSION
    P_CMD_MG
    P_CMD_HD
    P_CMD_NS
    P_CMD_EX
    P_CMD_NF

cdef ParserCmd parser_get_cmd(Parser *p, int *ret) noexcept nogil

cdef bytes parser_get_string(Parser *p) noexcept

cdef bytes parser_get_data(Parser *p) noexcept