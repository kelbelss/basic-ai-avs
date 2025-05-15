# 🦙 Basic Text-Moderation AVS

_A personal learning playground for EigenLayer & AVS development._

### Project scope

This repo implements a minimal AVS that turns on-chain text into a moderation task secured by EigenLayer restaked operators. The goal is not production readiness but to understand how the EigenLayer core contracts, operator life-cycle, slashing, and reward accounting fit together.

### High‑level flow

Task creation - Any user calls `createNewTask(string)` on ServiceManager. The call emits NewTaskCreated with a struct hash kept on‑chain.

Off‑chain evaluation - TS bot (off‑chain/respondToTask.ts) listens for new tasks, runs the text through Llama Guard, decides whether the content is safe, signs the result, and calls `respondToTask`.

On‑chain verification - ServiceManager checks:

- The task hash matches the stored value.
- The caller is a registered operator.
- The signature is valid for either an EOA (ECDSA) or contract wallet (EIP‑1271).

### Future phases:

- Slashing: missed deadlines trigger IEigenLayerSlasher.slash()
- Redistribution: slashed funds flow to Redistributor.sol 
- Rewards: integrate the EigenLayer Rewards Coordinator




