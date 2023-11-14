cdef class ObjectPool:
    def __init__(self, int size):
        self.objects = []
        self.free_indices = []
        self.size = size
    
    cpdef int put(self, object obj):
        cdef int index

        if len(self.free_indices) == 0:
            index = len(self.objects)
            self.objects.append(obj)
            return index

        index = self.free_indices.pop()
        self.objects[index] = obj

        return index

    cpdef void free(self, int index):
        self.objects[index] = None
        self.free_indices.append(index)

    def get_objects(self):
        return self.objects

    def get_free_indices(self):
        return self.free_indices