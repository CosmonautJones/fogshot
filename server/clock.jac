"""Server clock for reveal authorization. Tests pin it. HTTP callers cannot."""

::py::
def _wall_ms():
    import time
    return int(time.time() * 1000)
::py::

glob _pinned: int = -1;

def server_now() -> int {
    if _pinned >= 0 {
        return _pinned;
    }
    return _wall_ms() as int;
}

def pin_clock(ms: int) -> None {
    _pinned = ms;
}
