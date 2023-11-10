from typing import Callable, Any

import cmem  # type: ignore


class Client:
    _client: Any

    def __init__(self, new_conn: Callable[[], Any]):
        self._client = cmem.Client(new_conn)
