# Private Insurance Eligibility (Zama FHEVM)

**Privacy‑preserving insurance pre‑check** on Ethereum Sepolia using Zama’s FHEVM. Applicants submit encrypted attributes (age, prior claims, credit score). The smart contract evaluates eligibility **under encryption** and returns an encrypted boolean that only the applicant (or everyone, if made public) can decrypt via the Relayer SDK.

> Network: **Sepolia**
> Contract (deployed): **`0x54863E5132ceADb20158034C60E2366AAA179a98`**
> Frontend uses **Relayer SDK 0.2.0** and **ethers v6** (ESM).

---

## Features

* 🔐 **Encrypted inputs**: age (uint8), prior claims (uint8), credit score (uint16)
* ⚖️ **Encrypted rules**: owner sets thresholds either privately (encrypted) or via dev helper (plain)
* ✅ **Encrypted decision**: contract computes *eligible / not eligible* as an **`ebool`**
* 🧾 **Handles everywhere**: the dapp surfaces bytes32 handles for audit/decrypt
* 🖥️ **Relayer flows**: supports **publicDecrypt** (when marked public) and **userDecrypt** with **EIP‑712**

---

## Architecture

```
Frontend (ESM, ethers v6, Relayer SDK 0.2.0)
   ├─ createEncryptedInput(contract, user)
   │    ├─ add8(age), add8(claims), add16(score)
   │    └─ encrypt() -> { handles, inputProof }
   └─ call checkEligibility(handle, proof)

FHEVM Smart Contract (Zama FHE.sol)
   ├─ fromExternal(ext, proof)
   ├─ compare under encryption (FHE.lt / ge / and / etc.)
   └─ allow + (optional) makePubliclyDecryptable(result)

Relayer
   ├─ publicDecrypt(handles)
   └─ userDecrypt(pairs, kp, EIP‑712 signature)
```

---

## Smart Contract API

> Solidity uses the official Zama lib: `import { FHE, euint8, euint16, ebool, externalEuint8, externalEuint16 } from "@fhevm/solidity/lib/FHE.sol"` and `SepoliaConfig`.

### Read‑only

* `function version() external pure returns (string)` – build marker.
* `function owner() external view returns (address)` – contract owner.
* `function getRuleHandles() external view returns (bytes32 minAgeH, bytes32 maxClaimsH, bytes32 minScoreH)` – encrypted thresholds (if set).

### Owner actions

* `function setRulesEncrypted(bytes32 minAgeExt, bytes32 maxClaimsExt, bytes32 minScoreExt, bytes proof) external`
  Accepts **external** encrypted values + attestation proof from the Relayer SDK.
* `function setRulesPlain(uint8 minAge, uint8 maxClaims, uint16 minScore) external`
  Dev helper for quick testing.
* `function makeRulesPublic() external`
  Marks threshold ciphertexts as publicly decryptable.

### Applicant flow

* `function checkEligibility(bytes32 ageExt, bytes32 claimsExt, bytes32 scoreExt, bytes proof) external returns (ebool ok)`
  Emits `EligibilityChecked(address indexed user, bytes32 resultHandle)`.

> **Note**: `FHE.allow(ok, msg.sender)` lets the caller decrypt privately via `userDecrypt`. If the owner also calls `makeRulesPublic()`, auditors can `publicDecrypt` rule handles.

---

## Frontend Overview

The app is a single‑file HTML (placed at **`frontend/public/index.html`**) with a clean, original design. It:

* connects MetaMask → ensures Sepolia;
* initializes Relayer SDK 0.2.0 (`initSDK` + `createInstance({...SepoliaConfig, relayerUrl, network})`);
* encrypts inputs with `add8/add8/add16` and submits to the contract;
* parses `EligibilityChecked` to obtain `resultHandle`;
* decrypts the result with **userDecrypt (EIP‑712)** and shows ✅/❌.

Console logging is verbose and namespaced (e.g., `[APP]`, `[FHE]`) for debugging.

---

## Prerequisites

* **Node.js 18+** (or any recent LTS)
* **MetaMask** in your browser
* Access to **Sepolia** test network (wallet funded with test ETH)

---

## Local Setup

```bash
# clone your repo
git clone <your-repo-url>
cd <your-repo>/frontend

# serve the static index.html (choose any)
# 1) simple python
python3 -m http.server 8080 -d public
# 2) or use a lightweight static server
npx serve public -l 8080
```

Open [http://localhost:8080](http://localhost:8080) in your browser.

> The frontend is self‑contained (no build step required). If you prefer a dev server with hot reload, wrap the file into your favorite toolchain.

---

## Environment

The frontend embeds sensible defaults:

* **Contract**: `0x54863E5132ceADb20158034C60E2366AAA179a98`
* **Network**: Sepolia (`chainId 11155111`)
* **Relayer URL**: `https://relayer.testnet.zama.cloud`

If you need to switch addresses/URLs, adjust the small `CONFIG` object at the top of the HTML.

---

## Run the Frontend

1. Open the app and **Connect** MetaMask.
2. If prompted, approve network switch to **Sepolia**.
3. (Admin) Set rules:

   * **Set Rules (encrypted)**: encrypt thresholds in the browser and submit.
   * **Set Rules (dev)**: plain thresholds for testing.
   * Optionally **Make Public** to allow `publicDecrypt` on rule handles.
4. (Applicant) Enter your **Age**, **Claims**, **Credit Score** → **Check Eligibility**.
5. The dapp displays tx hash, the emitted `resultHandle`, and the decrypted decision.

---

## Troubleshooting

* **`missing revert data` / call exception**

  * Wrong **contract address** or **ABI**; wrong **network**; or the **proof/handle** tuple does not match the contract’s verifying addresses.
  * Ensure you’re on **Sepolia**, the contract is correct, and you pass the exact `{handle, proof}` pair returned by `encrypt()`.
* **Relayer errors**

  * Confirm **Relayer SDK 0.2.0**. Ensure `createInstance({...SepoliaConfig, relayerUrl, network: window.ethereum})` is used.
  * For **userDecrypt**, make sure you generate a keypair and sign the **EIP‑712** message provided by `createEIP712`.
* **No `EligibilityChecked` found**

  * Check the event topic name and that you filtered logs by your contract address.

---

## Security Notes

* Keep plaintext inputs **off‑chain**; always use the Relayer to build encrypted inputs.
* Avoid exposing private keys. The EIP‑712 flow signs a typed message; it does **not** leak keys.
* Consider making only the final decision public, while keeping thresholds private in production.

---

## Tech Stack

* **Solidity** with Zama **FHEVM** (`@fhevm/solidity`) and **SepoliaConfig**
* **Relayer SDK** `0.2.0`
* **ethers v6 (ESM)**
* Single‑page static frontend (no framework required)

---

## License

MIT — see `LICENSE`.
