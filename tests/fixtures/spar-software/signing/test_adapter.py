import unittest

from adapter import sign


class Signer:
    def __init__(self):
        self.signed = set()
        self.saved = set()

    def run(self, arguments):
        command, *operands = arguments
        if command != "sign":
            raise ValueError(command)
        image = operands[-1]
        self.signed.add(image)


class SigningTests(unittest.TestCase):
    def test_signs(self):
        tool = Signer()
        sign(tool, "new.efi")
        self.assertIn("new.efi", tool.signed)


if __name__ == "__main__":
    unittest.main()
