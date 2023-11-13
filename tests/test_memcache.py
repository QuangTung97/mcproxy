import socket
import unittest

import cmem  # type: ignore


class TestMemcache(unittest.TestCase):
    def new_socket(self):
        self.conn = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

        host_ip = socket.gethostbyname('localhost')
        self.conn.settimeout(0.1)
        self.conn.connect((host_ip, 11211))
        return self.conn

    def test_normal(self) -> None:
        c = cmem.Client(self.new_socket)

        conns = cmem.get_global_conns()
        self.assertEqual(1, len(conns))
        self.assertIs(self.conn, conns[0])

        del c

        self.assertEqual([None], conns)
        self.assertEqual([0], cmem.get_global_free_conns())

        c2 = cmem.Client(self.new_socket)

        self.assertEqual(1, len(conns))
        self.assertIs(self.conn, conns[0])
        self.assertEqual([], cmem.get_global_free_conns())

        del c2
        self.assertEqual([None], conns)
        self.assertEqual([0], cmem.get_global_free_conns())

    def test_version(self):
        c = cmem.Client(self.new_socket)
        self.assertEqual('1.6.18', c.version())


class TestCMemParser(unittest.TestCase):
    def test_version(self):
        p = cmem.ParserTest()
        p.handle(b'VERSION 123\r\n')
