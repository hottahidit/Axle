from flask import Flask
from bot import start
from database.db import db
import config

app = Flask(__name__)


def main():
    start()
    app.run(host="0.0.0.0", port=config.PORT, debug=False)


if __name__ == "__main__":
    main()
