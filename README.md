## Blober - On-chain Blob Verification Library in Solidity ![Tests](https://github.com/markolazic01/blob-verifier/workflows/CI/badge.svg)
**Blober** is a Solidity library for Ethereum blob verification (and more), by introducing a well designed set of blob point verification flows it eases helps the L2 settlements. 

---
### Problem Solution
So far L2s usually build their own blob verification flows, in a non-standardized and sometimes messy way, Blober serves as a library that abstracts away the precompile interactions and makes the verification clean and efficient.

Blober's special feature is in multi-point verifications, across multiple blobs, where by utilizing the BLS precompiles from EIP-2537 it merges the blob points into a single point, making a verification process of multiple points less costly (by much).

Blober also contains other utils that can help you checksum the specific blob hash, get a versioned hash from the blob data hash, check if blob is present in the tx and more! 

With introduction of 14 blob per block limit, Blober multi-point verification becomes increasingly effective, for L2s using Blober instead of iterative point validation, gas consumption can be reduced by up to **80%**!

Danksharding and Block-in-Blob EIPs can further leverage usage of Blober, potentially requiring the development of new features.

---
### Build
```
$ forge build
```

### Test
```
$ forge test --fork-url <ETH_RPC>
```

---
### Usage

#### Install
```
$ forge install markolazic01/blob-verifier
```
#### Import
``` solidity
pragma solidity ^0.8.30;

import { BlobVerifier } from "blob-verifier/BlobVerifier.sol";
```

---
### License
MIT
