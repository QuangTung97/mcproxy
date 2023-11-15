import socket
import unittest

import cmem  # type: ignore
import cutil  # type: ignore


class TestMemcache(unittest.TestCase):
    def new_socket(self):
        self.conn = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

        host_ip = socket.gethostbyname('localhost')
        self.conn.settimeout(0.1)
        self.conn.connect((host_ip, 11211))
        return self.conn

    def test_new_client(self) -> None:
        c = cmem.Client(self.new_socket())

        self.assertEqual(9304, cutil.py_get_mem())

        pool = cmem.get_client_pool()
        conns = pool.get_objects()

        self.assertEqual(1, len(conns))
        self.assertIsNotNone(conns[0])

        del c

        self.assertEqual([None], conns)
        self.assertEqual([0], pool.get_free_indices())

        c2 = cmem.Client(self.new_socket())

        self.assertEqual(1, len(conns))
        self.assertIsNotNone(conns[0])
        self.assertEqual([], pool.get_free_indices())

        self.assertEqual(9304, cutil.py_get_mem())

        del c2
        self.assertEqual([None], conns)
        self.assertEqual([0], pool.get_free_indices())

        self.assertEqual(0, cutil.py_get_mem())

    def test_new_pipeline(self) -> None:
        c = cmem.Client(self.new_socket())
        p = c.pipeline()
        self.assertIsNotNone(p)

        pool = cmem.get_client_pool()
        conns = pool.get_objects()

        self.assertEqual(1, len(conns))
        self.assertIsNotNone(conns[0])

        del c
        self.assertIsNotNone(conns[0])

        del p
        self.assertEqual([None], conns)

        self.assertEqual(0, cutil.py_get_mem())
