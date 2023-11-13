import unittest

import cutil  # type: ignore


class TestCUtil(unittest.TestCase):
    def test_alloc(self) -> None:
        self.assertEqual(0, cutil.py_get_mem())
