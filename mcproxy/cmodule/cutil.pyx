from libc.stdlib cimport malloc, free, exit
from libc.string cimport memset


cdef unsigned int global_current_mem = 0


cdef void *alloc_object(size_t n) noexcept nogil:
    global global_current_mem
    global_current_mem += n
    return malloc(n)


cdef void free_object(void *ptr, size_t n) noexcept nogil:
    global global_current_mem
    global_current_mem -= n
    memset(ptr, 0, n)
    free(ptr)


def py_get_mem():
    global global_current_mem
    return global_current_mem


cdef int bytes_equal(const char *a, int a_len, const char *b, int b_len) noexcept nogil:
    cdef int i

    if a_len != b_len:
        return False

    for i in range(a_len):
        if a[i] != b[i]:
            return False
    return True


# ===================================
# Shared Pointer
# ===================================

cdef struct SharedPtr:
    void *self_ptr
    void *obj
    RefCounter *ref


cdef struct WeakPtr:
    void *self_ptr
    void *obj
    RefCounter *ref


cdef void make_shared(
    SharedPtr *ptr, void *obj, RefCounter *ref,
    destroy_func destroy_fn, free_func free_fn,
) noexcept nogil:
    ptr.self_ptr = <void *>ptr
    ptr.obj = obj

    ref.count = 1
    ref.weak_count = 0
    ref.destroy_fn = destroy_fn
    ref.free_fn = free_fn

    ptr.ref = ref


cdef void *ptr_get(const SharedPtr *ptr) noexcept nogil:
    if <void *>ptr != ptr.self_ptr:
        with gil:
            print('[ERROR] ptr_get on invalid pointer')
        exit(-1)

    return ptr.obj


cdef void ptr_clone(SharedPtr *new_ptr, const SharedPtr *ptr) noexcept nogil:
    new_ptr.self_ptr = <void *>new_ptr
    new_ptr.obj = ptr.obj
    new_ptr.ref = ptr.ref
    new_ptr.ref.count += 1


cdef void ptr_free(SharedPtr *ptr) noexcept nogil:
    if <void *>ptr != ptr.self_ptr:
        with gil:
            print('[ERROR] ptr_free on invalid pointer')
        exit(-1)
    
    if ptr.obj == NULL:
        return

    if ptr.ref.count == 0:
        with gil:
            print('[ERROR] double free shared pointer')
        exit(-1)
    
    ptr.ref.count -= 1

    if ptr.ref.count == 0:
        ptr.ref.destroy_fn(ptr.obj)

        if ptr.ref.weak_count == 0:
            ptr.ref.free_fn(ptr.obj)


cdef void make_weak_ptr(WeakPtr *new_ptr, const SharedPtr *ptr) noexcept nogil:
    new_ptr.self_ptr = <void *>new_ptr
    new_ptr.obj = ptr.obj
    new_ptr.ref = ptr.ref
    new_ptr.ref.weak_count += 1


cdef void weak_ptr_clone(SharedPtr *new_ptr, const WeakPtr *ptr) noexcept nogil:
    new_ptr.self_ptr = <void *>new_ptr

    if ptr.ref.count == 0:
        new_ptr.obj = NULL
        return
    
    ptr.ref.count += 1
    new_ptr.ref = ptr.ref
    new_ptr.obj = ptr.obj


cdef void weak_ptr_free(WeakPtr *ptr) noexcept nogil:
    if <void *>ptr != ptr.self_ptr:
        with gil:
            print('[ERROR] weak_ptr_free on invalid weak pointer')
        exit(-1)
    
    if ptr.ref.weak_count == 0:
        with gil:
            print('[ERROR] double free on weak pointer')
        exit(-1)

    ptr.ref.weak_count -= 1
    if ptr.ref.count == 0 and ptr.ref.weak_count == 0:
        ptr.ref.free_fn(ptr.obj)


# Testing

cdef struct TestData:
    RefCounter ref
    int age
    int height


cdef void test_data_destroy(void *obj) noexcept nogil:
    cdef TestData *o = <TestData *>obj
    with gil:
        print('Destroy Test Data:', o.age)


cdef void test_data_free(void *obj) noexcept nogil:
    cdef TestData *o = <TestData *>obj
    with gil:
        print('Free Test Data:', o.age)
    free_object(obj, sizeof(TestData))
    


cdef class TestContainer:
    cdef SharedPtr ptr
    cdef WeakPtr weak_ptr
    cdef SharedPtr new_ptr

    def __cinit__(self, int age):
        cdef TestData *d = <TestData *>alloc_object(sizeof(TestData))
        d.age = age
        make_shared(&self.ptr, d, &d.ref, test_data_destroy, test_data_free)
    
    def get_age(self):
        cdef TestData *d = <TestData *>ptr_get(&self.ptr)
        return d.age
    
    def get_weak(self):
        make_weak_ptr(&self.weak_ptr, &self.ptr)

    def get_from_weak(self):
        weak_ptr_clone(&self.new_ptr, &self.weak_ptr)
    
    def release_weak(self):
        weak_ptr_free(&self.weak_ptr)
    
    def release(self):
        weak_ptr_free(&self.weak_ptr)
        ptr_free(&self.new_ptr)
    
    def get_new_age(self):
        cdef TestData *d = <TestData *>ptr_get(&self.new_ptr)
        return d.age

    def destroy(self):
        ptr_free(&self.ptr)
