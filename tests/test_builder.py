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
        return 0

    def test_empty(self) -> None:
        b = cbuilder.BuilderTest(self.write_func, 1024)
        del b
        self.assertEqual(0, cutil.py_get_mem())

    def test_add_mget(self) -> None:
        b = cbuilder.BuilderTest(self.write_func, 1024)

        ret = b.add_mget(b'key01')
        self.assertEqual(0, ret)

        self.assertEqual([], self.write_list)

        ret = b.finish()
        self.assertEqual(0, ret)

        self.assertEqual([b'mg key01 v\r\n'], self.write_list)

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
        self.assertEqual(0, ret)

        self.assertEqual([b'mg key01 v\r\nmg key02 v\r\n'], self.write_list)

        # write again
        ret = b.add_mget(b'key03')
        self.assertEqual(0, ret)

        ret = b.finish()
        self.assertEqual(0, ret)

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

        self.assertEqual(0, b.add_mget(b'k2'))
        self.assertEqual([b'mg key01 v\r\n'], self.write_list)

        self.assertEqual(0, b.finish())
        self.assertEqual([b'mg key01 v\r\n', b'mg k2 v\r\n'], self.write_list)

        self.assertEqual(0, b.add_mget(b'key02'))
        self.assertEqual(0, b.add_mget(b'key03'))

        self.assertEqual(0, b.finish())
        self.assertEqual([
            b'mg key01 v\r\n', b'mg k2 v\r\n',
            b'mg key02 v\r\n', b'mg key03 v\r\n',
        ], self.write_list)

        del b
        self.assertEqual(0, cutil.py_get_mem())

    def test_add_mget_near_exceed_limit_on_first_call(self) -> None:
        cmd1 = b'mg key01 v\r\n'

        b = cbuilder.BuilderTest(self.write_func, len(cmd1) + 1)

        self.assertEqual(0, b.add_mget(b'key01'))
        self.assertEqual([], self.write_list)

        self.assertEqual(0, b.add_mget(b'k2'))
        self.assertEqual([b'mg key01 v\r\nm'], self.write_list)

        self.assertEqual(0, b.finish())
        self.assertEqual([b'mg key01 v\r\nm', b'g k2 v\r\n'], self.write_list)

        del b
        self.assertEqual(0, cutil.py_get_mem())

    def test_add_mget_with_N(self) -> None:
        b = cbuilder.BuilderTest(self.write_func, 1024)

        self.assertEqual(0, b.add_mget(b'key01', N=12))
        self.assertEqual(0, b.finish())

        self.assertEqual([b'mg key01 N12 v\r\n'], self.write_list)

        del b
        self.assertEqual(0, cutil.py_get_mem())

    def test_add_mget_with_N_zero(self) -> None:
        b = cbuilder.BuilderTest(self.write_func, 1024)

        self.assertEqual(0, b.add_mget(b'key01', N=0))
        self.assertEqual(0, b.finish())

        self.assertEqual([b'mg key01 v\r\n'], self.write_list)

        del b
        self.assertEqual(0, cutil.py_get_mem())

    def test_add_mget_with_N_negative(self) -> None:
        b = cbuilder.BuilderTest(self.write_func, 1024)

        self.assertEqual(0, b.add_mget(b'key01', N=-2))
        self.assertEqual(0, b.finish())

        self.assertEqual([b'mg key01 v\r\n'], self.write_list)

        del b
        self.assertEqual(0, cutil.py_get_mem())
