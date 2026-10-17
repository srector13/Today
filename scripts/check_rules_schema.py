"""Checks the rules files against Rules/household.schema.json.

usage: check_rules_schema.py SCHEMA RULES_JSON SAMPLE_HOUSEHOLD_SWIFT

Validates the real rules file and the sample household (the JSON literal in
SampleHousehold.swift), and confirms the schema still rejects a misspelt key
and a malformed time, so it keeps catching the mistakes hand edits make.
"""

import json
import re
import sys

from jsonschema import Draft202012Validator


def check(validator, name, document, expect_valid=True):
    errors = sorted(validator.iter_errors(document), key=lambda e: list(e.path))
    valid = not errors
    passed = valid == expect_valid
    detail = "" if valid else "; ".join(f"{list(e.path)}: {e.message[:100]}" for e in errors[:3])
    print("PASS" if passed else "FAIL", name, detail)
    return passed


def main(schema_path, rules_path, sample_swift_path):
    schema = json.load(open(schema_path))
    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema)

    rules = json.load(open(rules_path))
    swift = open(sample_swift_path).read()
    match = re.search(r'rulesJSON = """\n(.*?)\n    """', swift, re.S)
    if not match:
        print("FAIL could not find rulesJSON in", sample_swift_path)
        return 1
    sample = json.loads(match.group(1))

    misspelt = json.loads(json.dumps(sample))
    misspelt["pickupLoop"]["fallbakStart"] = "17:00"
    bad_time = json.loads(json.dumps(sample))
    bad_time["blocks"][0]["start"] = "8.30"

    results = [
        check(validator, "household.json", rules),
        check(validator, "sample household", sample),
        check(validator, "misspelt key is rejected", misspelt, expect_valid=False),
        check(validator, "malformed time is rejected", bad_time, expect_valid=False),
    ]
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:4]))
