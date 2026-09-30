# Local signing adapter

`adapter.sign(tool, image)` signs a selected image using the supplied dependency. It must never add the image to the dependency's saved-file list: that list is consumed by a separate signer with different selection rules. The current adapter is a candidate for adoption.

`dependency-contract.md` is the authoritative synthetic dependency contract for this exercise. No real signing tools, keys, boot files or upstream versions are involved. `python3 test_adapter.py` checks successful signing with the supplied test double. Assess the implementation and whether the test evidence protects the saved-list invariant, including a regression in the command's arguments.
