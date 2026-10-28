import json
import logging
import os

import azure.functions as func
from azure.data.tables import TableClient

import counter

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)


def _table() -> TableClient:
    return TableClient.from_connection_string(
        os.environ["COSMOS_TABLE_CONNECTION"], table_name="visitors"
    )


@app.route(route="visitors", methods=["GET", "POST"])
def visitors(req: func.HttpRequest) -> func.HttpResponse:
    try:
        table = _table()
        count = counter.increment(table) if req.method == "POST" else counter.read(table)
        return func.HttpResponse(json.dumps({"count": count}), mimetype="application/json")
    except Exception:
        logging.exception("visitor counter failed")
        return func.HttpResponse(
            json.dumps({"error": "internal error"}), status_code=500, mimetype="application/json"
        )
