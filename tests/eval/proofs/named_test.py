"""Proof for the handoff pair. Usage: named_test.py <fixture repository>
Exit 0: the test that the handoff names exists. Exit 10: it does not."""
import os
import sys

sys.path.insert(0, sys.argv[1])
from tests import test_app  # noqa: E402

# The fixture's own tests, not another package of that name on this Python's path.
if not os.path.samefile(os.path.dirname(os.path.dirname(os.path.abspath(test_app.__file__))), sys.argv[1]):
    print(f"read the tests of another place: {test_app.__file__}")
    sys.exit(2)
found = hasattr(test_app.AppTest, "test_limit_is_per_user")
print("the test the handoff names " + ("exists" if found else "does not exist"))
sys.exit(0 if found else 10)
