import os
import sys

from azure.core.exceptions import ResourceModifiedError, ResourceNotFoundError

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import counter  # noqa: E402


class _Entity(dict):
    metadata = {"etag": "x"}


class FakeTable:
    def __init__(self, conflicts: int = 0):
        self.row = None
        self.conflicts = conflicts

    def get_entity(self, pk, rk):
        if self.row is None:
            raise ResourceNotFoundError("missing")
        return _Entity(self.row)

    def create_entity(self, entity):
        self.row = dict(entity)

    def update_entity(self, entity, **kwargs):
        if self.conflicts:
            self.conflicts -= 1
            raise ResourceModifiedError("etag mismatch")
        self.row = dict(entity)


def test_first_visit_initialises_to_one():
    assert counter.increment(FakeTable()) == 1


def test_increments_existing_value():
    t = FakeTable()
    counter.increment(t)
    assert counter.increment(t) == 2


def test_read_returns_zero_when_uninitialised():
    assert counter.read(FakeTable()) == 0


def test_retries_after_concurrent_update():
    t = FakeTable()
    counter.increment(t)
    t.conflicts = 2
    assert counter.increment(t) == 2
