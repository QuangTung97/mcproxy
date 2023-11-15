import math
import unittest
from typing import List

import cbuilder  # type: ignore
import cutil  # type: ignore


class TestBuilder(unittest.TestCase):
    write_list: List[bytes]

    def setUp(self) -> None:
        self.write_list = []

    def write_func(self, data: bytes) -> int:
        self.write_list.append(data)
        return len(data)

    def test_empty(self) -> None:
        b = cbuilder.BuilderTest(self.write_func, 1024)
        del b
        self.assertEqual(0, cutil.py_get_mem())

    def test_add_mget(self) -> None:
        b = cbuilder.BuilderTest(self.write_func, 1024)

        cmd1 = b'mg key01 v\r\n'

        ret = b.add_mget(b'key01')
        self.assertEqual(0, ret)

        self.assertEqual([], self.write_list)

        ret = b.finish()
        self.assertEqual(1, ret)

        self.assertEqual([cmd1], self.write_list)

        del b
        self.assertEqual(0, cutil.py_get_mem())

    def test_add_mget_multi(self) -> None:
        b = cbuilder.BuilderTest(self.write_func, 1024)

        ret = b.add_mget(b'key01')
        self.assertEqual(0, ret)

        ret = b.add_mget(b'key02')
        self.assertEqual(0, ret)

        self.assertEqual([], self.write_list)

        ret = b.finish()
        self.assertEqual(1, ret)

        self.assertEqual([b'mg key01 v\r\nmg key02 v\r\n'], self.write_list)

        # write again
        ret = b.add_mget(b'key03')
        self.assertEqual(0, ret)

        ret = b.finish()
        self.assertEqual(1, ret)

        self.assertEqual([
            b'mg key01 v\r\nmg key02 v\r\n',
            b'mg key03 v\r\n',
        ], self.write_list)

        del b
        self.assertEqual(0, cutil.py_get_mem())

    def test_add_mget_exceed_limit(self) -> None:
        cmd1 = b'mg key01 v\r\n'

        b = cbuilder.BuilderTest(self.write_func, len(cmd1))

        self.assertEqual(0, b.add_mget(b'key01'))
        self.assertEqual([], self.write_list)

        self.assertEqual(1, b.add_mget(b'k2'))
        self.assertEqual([b'mg key01 v\r\n'], self.write_list)

        self.assertEqual(1, b.finish())
        self.assertEqual([b'mg key01 v\r\n', b'mg k2 v\r\n'], self.write_list)

        self.assertEqual(0, b.add_mget(b'key02'))
        self.assertEqual(1, b.add_mget(b'key03'))

        self.assertEqual(1, b.finish())
        self.assertEqual([
            b'mg key01 v\r\n', b'mg k2 v\r\n',
            b'mg key02 v\r\n', b'mg key03 v\r\n',
        ], self.write_list)

        del b
        self.assertEqual(0, cutil.py_get_mem())

    def test_add_mget_near_exceed_limit_on_second_call(self) -> None:
        cmd1 = b'mg key01 v\r\n'

        b = cbuilder.BuilderTest(self.write_func, len(cmd1) + 1)

        self.assertEqual(0, b.add_mget(b'key01'))
        self.assertEqual([], self.write_list)

        self.assertEqual(1, b.add_mget(b'k2'))
        self.assertEqual([b'mg key01 v\r\nm'], self.write_list)

        self.assertEqual(1, b.finish())
        self.assertEqual([b'mg key01 v\r\nm', b'g k2 v\r\n'], self.write_list)

        del b
        self.assertEqual(0, cutil.py_get_mem())

    def test_add_mget_with_N(self) -> None:
        b = cbuilder.BuilderTest(self.write_func, 1024)

        self.assertEqual(0, b.add_mget(b'key01', N=12))
        self.assertEqual(1, b.finish())

        self.assertEqual([b'mg key01 N12 v\r\n'], self.write_list)

        del b
        self.assertEqual(0, cutil.py_get_mem())

    def test_add_mget_with_N_zero(self) -> None:
        b = cbuilder.BuilderTest(self.write_func, 1024)

        self.assertEqual(0, b.add_mget(b'key01', N=0))
        self.assertEqual(1, b.finish())

        self.assertEqual([b'mg key01 v\r\n'], self.write_list)

        del b
        self.assertEqual(0, cutil.py_get_mem())

    def test_add_mget_with_N_negative(self) -> None:
        b = cbuilder.BuilderTest(self.write_func, 1024)

        self.assertEqual(0, b.add_mget(b'key01', N=-2))
        self.assertEqual(1, b.finish())

        self.assertEqual([b'mg key01 v\r\n'], self.write_list)

        del b
        self.assertEqual(0, cutil.py_get_mem())

    def test_add_mset(self) -> None:
        b = cbuilder.BuilderTest(self.write_func, 1024)

        self.assertEqual(0, b.add_mset(b'key01', b'data 01'))
        self.assertEqual(1, b.finish())

        self.assertEqual([b'ms key01 7\r\ndata 01\r\n'], self.write_list)

        del b
        self.assertEqual(0, cutil.py_get_mem())

    def test_add_mset_zero_size(self) -> None:
        b = cbuilder.BuilderTest(self.write_func, 1024)

        self.assertEqual(0, b.add_mset(b'key01', b''))
        self.assertEqual(1, b.finish())

        self.assertEqual([b'ms key01 0\r\n\r\n'], self.write_list)

        del b
        self.assertEqual(0, cutil.py_get_mem())

    def test_add_mset_with_limit(self) -> None:
        cmd = b'ms key01 98\r\n'

        b = cbuilder.BuilderTest(self.write_func, 29)

        self.assertEqual(1, b.add_mset(b'key01', b'A' * 97))
        self.assertEqual(1, b.finish())

        self.assertEqual(112, 97 + 2 + len(cmd))
        self.assertEqual(4, math.ceil(112 / 29))
        self.assertEqual(4, len(self.write_list))

        result = b''
        for e in self.write_list:
            result += e

        data = 'A' * 97
        self.assertEqual(f'ms key01 97\r\n{data}\r\n'.encode(), result)

        del b
        self.assertEqual(0, cutil.py_get_mem())

    def test_add_mset_with_cas(self) -> None:
        b = cbuilder.BuilderTest(self.write_func, 1024)

        self.assertEqual(0, b.add_mset(b'key01', b'data 01', cas=18))
        self.assertEqual(1, b.finish())

        self.assertEqual([b'ms key01 7 C18\r\ndata 01\r\n'], self.write_list)

        del b
        self.assertEqual(0, cutil.py_get_mem())

    def test_add_mset_with_cas_very_big(self) -> None:
        b = cbuilder.BuilderTest(self.write_func, 1024)

        self.assertEqual(0, b.add_mset(b'key01', b'data 01', cas=9223372036854775809))
        self.assertEqual(0, b.add_mset(b'key02', b'XX', cas=123))

        self.assertEqual(1, b.finish())

        self.assertEqual([
            b'ms key01 7 C9223372036854775809\r\ndata 01\r\n' +
            b'ms key02 2 C123\r\nXX\r\n'
        ], self.write_list)

        del b
        self.assertEqual(0, cutil.py_get_mem())

    def test_add_mset_very_big_value(self) -> None:
        b = cbuilder.BuilderTest(self.write_func, 1024)

        self.assertEqual(1, b.add_mset(b'key01', b'A' * 100_000, cas=12))

        self.assertEqual(1, b.finish())

        self.assertEqual(100023, len('mg key01 100000 C12\r\n\r\n') + 100_000)
        self.assertEqual(98, math.ceil(100023 / 1024))
        self.assertEqual(98, len(self.write_list))

        result = b''
        for e in self.write_list:
            result += e

        self.assertEqual(b'ms key01 100000 C12\r\n' + b'A' * 100_000 + b'\r\n', result)

        del b
        self.assertEqual(0, cutil.py_get_mem())

    def test_add_delete(self) -> None:
        b = cbuilder.BuilderTest(self.write_func, 1024)

        self.assertEqual(0, b.add_delete(b'key01'))
        self.assertEqual(1, b.finish())

        self.assertEqual([b'md key01\r\n'], self.write_list)

        del b
        self.assertEqual(0, cutil.py_get_mem())

    def test_add_multi_commands(self) -> None:
        b = cbuilder.BuilderTest(self.write_func, 1024)

        self.assertEqual(0, b.add_mget(b'key01', N=3))
        self.assertEqual(0, b.add_mset(b'key01', b'data 01', cas=1234))
        self.assertEqual(0, b.add_delete(b'key01'))

        self.assertEqual(1, b.finish())

        self.assertEqual([
            b'mg key01 N3 v\r\n' +
            b'ms key01 7 C1234\r\ndata 01\r\n' +
            b'md key01\r\n',
        ], self.write_list)

        del b
        self.assertEqual(0, cutil.py_get_mem())


class TestBuilderWithWriteFull(unittest.TestCase):
    write_list: List[bytes]
    resp_list: List[int]

    def setUp(self) -> None:
        self.write_list = []
        self.resp_list = []

    def write_func(self, data: bytes) -> int:
        index = len(self.write_list)
        self.write_list.append(data)
        return self.resp_list[index]

    def test_add_mget(self) -> None:
        b = cbuilder.BuilderTest(self.write_func, 1024)

        self.assertEqual(0, b.add_mget(b'key01'))
        self.assertEqual([], self.write_list)

        self.resp_list = [0]
        self.assertEqual(2, b.finish())
