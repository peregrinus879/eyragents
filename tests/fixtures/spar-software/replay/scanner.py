import json
import sys


def main():
    try:
        with open(sys.argv[1]) as source:
            record = json.load(source)
        for entry in record["menu"]:
            print(entry)
        return int(record.get("managed_comment_misplaced", False))
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
