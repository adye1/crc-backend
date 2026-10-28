from azure.core import MatchConditions
from azure.core.exceptions import ResourceExistsError, ResourceModifiedError, ResourceNotFoundError

PARTITION = "counter"
ROW = "total"


def increment(table, retries: int = 5) -> int:
    """Atomically add 1 to the visitor count and return the new value."""
    for _ in range(retries):
        try:
            entity = table.get_entity(PARTITION, ROW)
        except ResourceNotFoundError:
            try:
                table.create_entity({"PartitionKey": PARTITION, "RowKey": ROW, "count": 1})
                return 1
            except ResourceExistsError:
                continue  # another request created it first; retry as an update
        new_count = int(entity["count"]) + 1
        entity["count"] = new_count
        try:
            table.update_entity(
                entity,
                mode="merge",
                etag=entity.metadata["etag"],
                match_condition=MatchConditions.IfNotModified,
            )
            return new_count
        except ResourceModifiedError:
            continue  # lost a race with another request; retry
    raise RuntimeError("could not update counter after retries")


def read(table) -> int:
    try:
        return int(table.get_entity(PARTITION, ROW)["count"])
    except ResourceNotFoundError:
        return 0
