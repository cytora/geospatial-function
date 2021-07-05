import os
from api import app, Config


if __name__ == '__main__':
    host = os.getenv("HOST", "localhost")
    port = os.getenv("PORT", "8080")
    app.run(host=host, port=port, debug=False, threaded=True)

