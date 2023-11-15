import unittest

import cutil  # type: ignore


class TestCUtil(unittest.TestCase):
    def test_alloc(self) -> None:
        self.assertEqual(0, cutil.py_get_mem())


class TestSharedPointer(unittest.TestCase):
    def test_normal(self) -> None:
        c = cutil.TestContainer(21)
        self.assertEqual(21, c.get_age())

        c.destroy()
        self.assertEqual(0, cutil.py_get_mem())

    def test_weak_ptr_clone(self) -> None:
        c = cutil.TestContainer(21)

        c.get_weak()
        c.get_from_weak()

        self.assertEqual(21, c.get_new_age())

        self.assertEqual(40, cutil.py_get_mem())

        c.release()

        c.destroy()
        self.assertEqual(0, cutil.py_get_mem())

    def test_weak_ptr_and_release(self) -> None:
        c = cutil.TestContainer(21)

        c.get_weak()

        self.assertEqual(40, cutil.py_get_mem())

        c.release_weak()

        self.assertEqual(40, cutil.py_get_mem())

        c.destroy()
        self.assertEqual(0, cutil.py_get_mem())

    def test_weak_ptr_release_weak_after_destroy(self) -> None:
        c = cutil.TestContainer(21)

        c.get_weak()

        self.assertEqual(40, cutil.py_get_mem())

        c.destroy()

        print("Middle")

        self.assertEqual(40, cutil.py_get_mem())

        c.release_weak()

        self.assertEqual(0, cutil.py_get_mem())
