# tremulator_keys

Each phone's keys, and all encryption and decryption. The only package in the
repo that imports `openmls`.

- `Identity`: who the phone signs as. The app stores `secret` in secure storage.
- `KeyStore`: the encrypted database. `makeKeyPackage`, `start`, `join`, `rejoin`.
- `Conversation`: `add`, `remove`, `refreshKeys`, `encrypt`, `receive`, `snapshot`, `destroy`.
- `peekConversationId`, `peekEpoch`, `peekKind`: route a blob without decrypting it.

Changes are applied locally the moment they are made (the library merges its
own commit before returning). If the server rejects a commit because another
member's change for the same epoch arrived first, the phone rejoins from the
newest `Snapshot` another member published. See `docs/GATE2-PLAN.md`.
