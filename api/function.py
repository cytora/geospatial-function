
import json
import os

from apig_wsgi import make_lambda_handler

from app import app

lambda_handler = make_lambda_handler(app.wsgi_app)


def handler(event, context):
    debug = os.getenv("DEBUG", "")
    if debug.lower() == "true":
        evt = json.dumps(event)
        print(f'{evt}')
    return lambda_handler(event, context)
