# Synthetic signer interface, revision 1

The dependency accepts `sign [--save|-s] IMAGE`. Unknown options fail. A successful call marks IMAGE signed. With `--save` or `-s`, a previously unsigned image is also registered in the saved-file list. Without that option, signing does not change the list. An already-signed image succeeds without registering it, even when a save option is supplied.

The saved-file list persists independently of the image's signed status. These are distinct observable effects.
