import unittest

import cparser  # type: ignore
import cutil  # type: ignore


class TestCMemParser(unittest.TestCase):
    def test_version(self):
        p = cparser.ParserTest()

        self.assertEqual(0, p.get())

        p.handle(b'VERSION 123.abcd\r\n')

        self.assertEqual(1, p.get())
        self.assertEqual(b'123.abcd', p.get_string())
        self.assertEqual(0, p.get_len())

        # check memory usage
        self.assertGreater(cutil.py_get_mem(), 1024)
        self.assertLess(cutil.py_get_mem(), 2048)

        del p
        self.assertEqual(0, cutil.py_get_mem())

    def test_version_split(self):
        p = cparser.ParserTest()

        self.assertEqual(0, p.get())

        p.handle(b'V')
        self.assertEqual(0, p.get())

        p.handle(b'E')
        self.assertEqual(0, p.get())

        p.handle(b'R')
        self.assertEqual(0, p.get())

        p.handle(b'SION')
        self.assertEqual(0, p.get())

        p.handle(b'  ')
        self.assertEqual(0, p.get())

        p.handle(b'11.2')
        self.assertEqual(0, p.get())

        p.handle(b'2\r')
        self.assertEqual(0, p.get())

        p.handle(b'\nabcd')
        self.assertEqual(1, p.get())

        self.assertEqual(b'11.22', p.get_string())
        self.assertEqual(4, p.get_len())

    def test_version_missing_value(self):
        p = cparser.ParserTest()

        self.assertEqual(0, p.get())

        p.handle(b'VERSION\r\n')

        self.assertEqual(1, p.get())
        self.assertEqual(b'', p.get_string())
        self.assertEqual(0, p.get_len())

    def test_version_empty(self):
        p = cparser.ParserTest()

        self.assertEqual(0, p.get())

        p.handle(b'VERSION')

        p.handle(b'')

        p.handle(b'   123\r\n')

        self.assertEqual(1, p.get())
        self.assertEqual(b'123', p.get_string())
        self.assertEqual(0, p.get_len())

    def test_no_lf_after_cr(self):
        p = cparser.ParserTest()

        self.assertEqual(0, p.get())

        p.handle(b'VERSION')

        p.handle(b'')

        with self.assertRaises(ValueError) as ex:
            p.handle(b'   123\ra')

        self.assertEqual(('invalid LF state',), ex.exception.args)

    def test_va(self):
        p = cparser.ParserTest()

        self.assertEqual(0, p.get())

        p.handle(b'VA 3\r\nABC\r\n')

        self.assertEqual(2, p.get())
        self.assertEqual(0, p.get_len())
        self.assertEqual(b'ABC', p.get_data())

        del p
        self.assertEqual(0, cutil.py_get_mem())

    def test_zero_response(self):
        p = cparser.ParserTest()

        self.assertEqual(0, p.get())

        p.handle(b'VA 0\r\n\r\n')

        self.assertEqual(2, p.get())
        self.assertEqual(0, p.get_len())
        self.assertEqual(b'', p.get_data())

        del p
        self.assertEqual(0, cutil.py_get_mem())

    def test_va_split(self):
        p = cparser.ParserTest()

        self.assertEqual(0, p.get())

        p.handle(b'VA 5\r\n')

        self.assertEqual(0, p.get())

        p.handle(b'ABCDE\r\n')

        self.assertEqual(2, p.get())
        self.assertEqual(0, p.get_len())
        self.assertEqual(b'ABCDE', p.get_data())

        del p
        self.assertEqual(0, cutil.py_get_mem())

    def test_va_missing_cr(self):
        p = cparser.ParserTest()

        self.assertEqual(0, p.get())

        with self.assertRaises(ValueError) as ex:
            p.handle(b'VA 2\r\nAAB\n')

        self.assertEqual(('invalid CR state',), ex.exception.args)

    def test_va_missing_lf(self):
        p = cparser.ParserTest()

        self.assertEqual(0, p.get())

        with self.assertRaises(ValueError) as ex:
            p.handle(b'VA 2\r\nAA\rA')

        self.assertEqual(('invalid LF state',), ex.exception.args)

    def test_va_not_number(self):
        p = cparser.ParserTest()

        self.assertEqual(0, p.get())

        with self.assertRaises(ValueError) as ex:
            p.handle(b'VA A\r\n')

        self.assertEqual(('not a VA number',), ex.exception.args)

    def test_va_allow_space_after_num(self):
        p = cparser.ParserTest()

        self.assertEqual(0, p.get())

        p.handle(b'VA    3  \r\nABC\r\n')

        self.assertEqual(2, p.get())
        self.assertEqual(0, p.get_len())
        self.assertEqual(b'ABC', p.get_data())

        del p
        self.assertEqual(0, cutil.py_get_mem())

    def test_va_multi_times(self):
        p = cparser.ParserTest()

        self.assertEqual(0, p.get())

        first = b'VA 3\r\nABC\r\n'
        second = b'VA 2\r\nXX\r\n'
        third = b'VA  1  \r\nY\r\n'
        forth = b'VERSION 123\r\n'

        data = first + second + third + forth
        p.handle(data)

        self.assertEqual(2, p.get())
        self.assertEqual(len(second + third + forth), p.get_len())
        self.assertEqual(b'ABC', p.get_data())

        self.assertEqual(2, p.get())
        self.assertEqual(len(third + forth), p.get_len())
        self.assertEqual(b'XX', p.get_data())

        self.assertEqual(2, p.get())
        self.assertEqual(len(forth), p.get_len())
        self.assertEqual(b'Y', p.get_data())

        self.assertEqual(1, p.get())
        self.assertEqual(0, p.get_len())
        self.assertEqual(b'Y', p.get_data())
        self.assertEqual(b'123', p.get_string())

        del p
        self.assertEqual(0, cutil.py_get_mem())

    def test_do_nothing(self):
        p = cparser.ParserTest()

        self.assertEqual(0, p.get_len())
        self.assertEqual(b'', p.get_data())
        self.assertEqual(b'', p.get_string())

        del p
        self.assertEqual(0, cutil.py_get_mem())


class TestCMemParserHandleMSet(unittest.TestCase):
    def test_handle_hd(self):
        p = cparser.ParserTest()

        p.handle(b'HD abcd\r\n')

        self.assertEqual(3, p.get())
        self.assertEqual(0, p.get_len())
        self.assertEqual(b'', p.get_data())
        self.assertEqual(b'', p.get_string())

        del p
        self.assertEqual(0, cutil.py_get_mem())

    def test_handle_hd_no_space(self):
        p = cparser.ParserTest()

        p.handle(b'HD\r\n')

        self.assertEqual(3, p.get())
        self.assertEqual(0, p.get_len())
        self.assertEqual(b'', p.get_data())
        self.assertEqual(b'', p.get_string())

        del p
        self.assertEqual(0, cutil.py_get_mem())

    def test_handle_hx(self):
        p = cparser.ParserTest()

        with self.assertRaises(ValueError) as ex:
            p.handle(b'HX\r\n')

        self.assertEqual(('invalid character after H',), ex.exception.args)

        del p
        self.assertEqual(0, cutil.py_get_mem())

    def test_handle_ns(self):
        p = cparser.ParserTest()

        p.handle(b'NS abcd\r\n')

        self.assertEqual(4, p.get())
        self.assertEqual(0, p.get_len())
        self.assertEqual(b'', p.get_data())
        self.assertEqual(b'', p.get_string())

        del p
        self.assertEqual(0, cutil.py_get_mem())

    def test_handle_ns_no_space(self):
        p = cparser.ParserTest()

        p.handle(b'NS\r\n')

        self.assertEqual(4, p.get())
        self.assertEqual(0, p.get_len())
        self.assertEqual(b'', p.get_data())
        self.assertEqual(b'', p.get_string())

        del p
        self.assertEqual(0, cutil.py_get_mem())

    def test_handle_nx(self):
        p = cparser.ParserTest()

        with self.assertRaises(ValueError) as ex:
            p.handle(b'NX\r\n')

        self.assertEqual(('invalid character after N',), ex.exception.args)

        del p
        self.assertEqual(0, cutil.py_get_mem())

    def test_handle_ex(self):
        p = cparser.ParserTest()

        p.handle(b'EX abcd\r\n')

        self.assertEqual(5, p.get())
        self.assertEqual(0, p.get_len())
        self.assertEqual(b'', p.get_data())
        self.assertEqual(b'', p.get_string())

        del p
        self.assertEqual(0, cutil.py_get_mem())

    def test_handle_es_invalid(self):
        p = cparser.ParserTest()

        with self.assertRaises(ValueError) as ex:
            p.handle(b'ES abcd\r\n')

        self.assertEqual(('invalid character after E',), ex.exception.args)

        del p
        self.assertEqual(0, cutil.py_get_mem())

    def test_handle_nf(self):
        p = cparser.ParserTest()

        p.handle(b'NF abcd\r\n')

        self.assertEqual(6, p.get())
        self.assertEqual(0, p.get_len())
        self.assertEqual(b'', p.get_data())
        self.assertEqual(b'', p.get_string())

        del p
        self.assertEqual(0, cutil.py_get_mem())
