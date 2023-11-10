import unittest

import mcproxy.memcache as mc


class TestMemcache(unittest.TestCase):
    def setUp(self) -> None:
        pass

    def test_normal(self) -> None:
        mc.hello()
        self.assertEqual(1, 1)
