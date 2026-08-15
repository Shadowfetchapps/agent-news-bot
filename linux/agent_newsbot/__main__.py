from __future__ import annotations

import argparse
import json
import logging
import sys


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="agent-newsbot")
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("serve", help="Run the localhost API and periodic fetch loop")
    sub.add_parser("fetch", help="Run one fresh fetch and print JSON")
    sub.add_parser("status", help="Show last snapshot counts")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    if args.cmd == "serve":
        from .server import serve

        serve()
        return 0

    from .config import SHARED
    from .server import STATE

    if args.cmd == "fetch":
        snapshot = STATE.refresh()
        json.dump({"total_articles": snapshot.get("total_articles"), "desks": snapshot.get("desks")}, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return 0

    latest = SHARED / "latest.json"
    if latest.exists():
        data = json.loads(latest.read_text())
        json.dump(
            {
                "fetched_at": data.get("fetched_at"),
                "total_articles": data.get("total_articles"),
                "desks": data.get("desks"),
            },
            sys.stdout,
            indent=2,
        )
        sys.stdout.write("\n")
        return 0
    print("no snapshot yet", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
