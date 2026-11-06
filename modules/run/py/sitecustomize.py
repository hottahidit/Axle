# axle run: another port for a Python file that starts its own server.
#
# `axle run` runs such a file as it is (python app.py). When its port is taken and you
# choose another, the file isn't changed: axle run puts this folder first on PYTHONPATH
# and sets AXLE_RUN_PORT, and Python loads this file at startup. It gives that port to
# the server's run() when it's called: Flask's app.run, Flask-SocketIO's socketio.run,
# uvicorn.run. Debug reloaders start Python again with the same environment, so it holds
# for them too.
#
# It's also there without AXLE_RUN_PORT, for one thing: Flask-SocketIO refuses to start
# its development server when stdin isn't a terminal (as for a service in the background)
# unless run() gets allow_unsafe_werkzeug=True; it's given that, unless the code says
# otherwise. Then the sitecustomize Python would have loaded otherwise (if any) is loaded.

import os
import sys


def _axle_run_hook():
    port = os.environ.get("AXLE_RUN_PORT", "")
    port = int(port) if port.isdigit() else None
    import importlib.abc

    # module: (class or None for the module itself, function, index of `port` if passed
    # by position, counting self)
    targets = {
        "flask.app": ("Flask", "run", 2),            # Flask.run(self, host, port, ...)
        "flask_socketio": ("SocketIO", "run", 3),    # SocketIO.run(self, app, host, port)
        "uvicorn.main": (None, "run", None),         # uvicorn.run(app, *, port=...)
    }

    def with_port(fn, at):
        # Flask-SocketIO 5.3+ (it's a string in its run()'s code: kwargs.pop(...)).
        unsafe = "allow_unsafe_werkzeug" in getattr(getattr(fn, "__code__", None), "co_consts", ())

        def run(*args, **kwargs):
            if port is not None:
                if at is not None and len(args) > at:
                    args = args[:at] + (port,) + args[at + 1:]
                else:
                    kwargs["port"] = port
            if unsafe:
                kwargs.setdefault("allow_unsafe_werkzeug", True)
            return fn(*args, **kwargs)
        run.__wrapped__ = fn
        run.__name__ = getattr(fn, "__name__", "run")
        run.__doc__ = getattr(fn, "__doc__", None)
        return run

    class Finder(importlib.abc.MetaPathFinder):
        # Patches the module right after it's loaded, before anything imports from it.
        def find_spec(self, name, path, target=None):
            if name not in targets:
                return None
            for finder in sys.meta_path:
                if finder is self or not hasattr(finder, "find_spec"):
                    continue
                spec = finder.find_spec(name, path, target)
                if spec is not None:
                    break
            else:
                return None
            loader = spec.loader
            if loader is None or not hasattr(loader, "exec_module"):
                return spec
            exec_module = loader.exec_module

            def exec_and_patch(module):
                exec_module(module)
                try:
                    cls, attr, at = targets[name]
                    owner = getattr(module, cls) if cls else module
                    setattr(owner, attr, with_port(getattr(owner, attr), at))
                except Exception:
                    pass

            loader.exec_module = exec_and_patch
            return spec

    sys.meta_path.insert(0, Finder())


def _axle_run_next_sitecustomize():
    import importlib.machinery
    import importlib.util

    here = os.path.dirname(os.path.abspath(__file__))
    rest = [p for p in sys.path if os.path.abspath(p or ".") != here]
    spec = importlib.machinery.PathFinder.find_spec("sitecustomize", rest)
    if spec is None or spec.loader is None:
        return
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)


try:
    _axle_run_hook()
except Exception:
    pass
_axle_run_next_sitecustomize()
