# POCoin - COM3026 Summative Coursework

POCoin is a blockchain visualization tool that allows you to inspect how a cryptocurrency works.
It is currently hosted at <http://ec2-176-34-174-172.eu-west-1.compute.amazonaws.com>.

_Note: the site is not responsive and was designed for a 14 inch screen at the minimum._

## Run locally

```bash
docker compose up
```

- Frontend will be available at `localhost`
- Backend at `localhost:3000`

_Note: if you are using an M1+ Mac, the docker-compose will not work. You will have to locally build the images and spin up the containers separately._

## Development

Refer to the README in the corresponding folder for more information.

- [Frontend](frontend/README.md)
- [Backend](backend/README.md) _(includes instructions for running Paxos tests)_

### Implementation

The repository contains two components:

1. A backend elixir application holding the logic for POCoin.
2. A frontend web application to visualize the cryptocurrency in action.

For the backend, the following have been implemented:

##### `wallet.ex`

- Standard (not HD) crypto wallet managing keypairs.
- Can wait for pending change to be available before sending a transaction to the network.
- Retries transactions ignored by node (such as when an transaction uses old UTXO).
- Generates cryptographically correct transaction payloads.
- Pools nodes to update UTXOs and balance in near real-time.

##### `node.ex`

- A basic Blockchain node; holds the replicated blockchain.
- Verifies received transactions and broadcasts them to other nodes.
- Keeps mempool of transactions.
- Polls mempool to run PoW in order to create a block.
- Runs consensus when a block is mined.

##### `web-server.ex`

Simple Cowboy webserver that exposes various endpoints from `wallet.ex` and `node.ex`.

## Service API

### Wallet

```elixir
send(wallet, address, amount) # send a transaction to node
```

```elixir
generate_address(wallet) # generate an invoice address for a wallet
```

```elixir
add_keypair(wallet, keypair) # add a public, private keypair to a wallet
```

```elixir
balance(wallet) # returns the balance of a wallet (including pending balance)
```

```elixir
available_balance(wallet) # returns the ready-to-spend balance of this wallet
```

```elixir
addresses(wallet) # returns all addresses for this wallet
```

```elixir
available_utxos(wallet) # returns all UTXOs for this wallet
```

```elixir
history(wallet) # returns the past transactions for a wallet
```

```elixir
get_pending_tx(wallet) # returns the next pending transaction for a wallet
```

### Node

```elixir
get_new_blocks(n, height) # returns blocks in the blockchain above the input height
```

```elixir
get_blockchain(node) # returns the whole blockchain
```

```elixir
get_mempool(node) # returns transactions in the mempool
```

```elixir
get_utxos(node) # returns all current UTXOs in the blockchain
```

```elixir
get_working_on(node) # returns the block that a node is currently mining for
```

```elixir
get_mining_power(node) # returns the percentage of blocks mined by a node
```

### Webserver endpoints

```php
GET /wallet_stats?w=:wallet // Exposes internal data of a wallet
```

```php
GET /send?w=:wallet&to_addr=:address&amount=:amount // Send amount from wallet to an address
```

```php
GET /generate_address?w=:wallet // Generate a new address for a wallet
```

```php
GET /node_stats?n=:node // Exposes internal data of a node
```

```php
GET /blockchain?n=:node&height=:height // Get blockchain blocks above height
```

## About POCoin

POCoin is a Bitcoin-inspired proof of concept cryptocurrency. It uses proof-of-work and Paxos consensus to reach instant block finality.

The proof-of-concept name derives from the simplifications that have been applied to the blockchain:

- Every block only contains a single transaction
- Nodes act as both miners and validators
- Assumes a permissioned blockchain, as it is not fully Byzantine Fault Tolerant

### Tokenomics :rocket:

| Total supply | Distribution  | Fees    | Block rewards | Issuance (annual) | Inflation       |
| ------------ | ------------- | ------- | ------------- | ----------------- | --------------- |
| 1000 :yen:   | 100% Dev Fund | 0 :yen: | 0 :yen:       | 0 :yen:           | No :sunglasses: |

In short, there is a fixed supply of 1000 POCoins; fees and block rewards have not been implemented.

### Initial setup

Since there are no block rewards and a fixed supply, the genesis block assigns 1000 coins to Alice, which distributes 200 each to her friends Bob, Charlie, Marco and Georgi.

### Sybil control mechanisms

Not everyone can participate in the consensus algorithm. The network uses a standard proof-of-work algorithm to select the next proposer and validators.

#### Choosing the proposer

The difficulty of the PoW is fixed and requires nodes to find a hash of the block starting with 6 zeros. Whichever node finds the solution first can propose a block to the network. Proposed blocks without a valid nonce or referencing the wrong parent will be ignored.

#### Choosing the validators

Every node keeps track of the percentage of blocks mined by other nodes (mining power).
When a node finds a PoW solution and becomes a proposer, it also chooses 2 validators through weighted random selection, where the weight is the mining power of the node.  
This ensures that only nodes that are contributing to the network are selected as validators.

To even the playing field, this rule is only applied above height 10 and validators are instead randomly selected before then.

## Service assumptions

### Byzantine Fault Tolerance

The network is not Byzantine resistant. For instance:

- Paxos is used as the consensus algorithm.
- BEB is used as the broadcast algorithm.
- Validators selection has not been implemented (even though the data needed is present in the blockchain).

The cryptography used in the blockchain however accounts for some Byzantine behavior:

- You cannot double spend or create coins from thin air.
- You can only spend your own coins.
- You cannot modify other people's transactions.
- You can only propose a block if you solve the PoW puzzle.

### Liveness

**1. A correct transaction sent to a node will always be added to the blockchain given that at most a minority of blockchain nodes (running Paxos) can crash**

 - Our implementation of Paxos uses an increasing ballot when a node makes multiple proposals for the same instance. This ensures that the blockchain keeps making progress even if a node with a higher ballot crashes.

- Due to the PoW, it is very unlikely that multiple nodes will run consensus for the same instance at the same time. However, in the case that a node gets nacked, it will have to recalculate a PoW solution from scratch. The PoW acts as a back-off and will make it highly unlikely that a "collision" will happen again for the same Paxos instance.

- By mapping the block height to a Paxos instance, we prevent a node from proposing a block for an instance beyond or prior the current height (assuming no malicious nodes).

- Termination only holds if the PoW puzzle is sufficiently difficult to solve, as otherwise the back-off would not be long and varied enough, leading to nodes infinitely competing for the same Paxos instance.

**2. The PoW algorithm will eventually find a nonce solving the block**

- Our implementation of PoW only requires nodes to find a nonce producing a hash starting with 6 zeros. This is not a very difficult task and will always terminate in a timely manner.

### Safety

The following safety properties assume a permissioned setting (no bad actors).

**1. All nodes agree on the same blockchain**

- Forks are impossible due to running consensus for every block.

- In a byzantine setting, nodes could only be able to _eventually_ agree and a way to handle forks would have to be implemented.

**2. You cannot double spend coins**

- This property holds due to the nodes keeping track of the valid UTXOs and only allowing transactions that spend valid UTXOs. This is possible thanks to the blockchain, a replicated state machine keeping track of all past transactions and their outputs.

- If we assume that bad actors are present (and replace Paxos with PBFT), this property would only hold if more than 2/3 of the processing power is held by honest nodes (as you need computing power to join consensus).

**3. Only valid blocks can be added to the blockchain**

- Blocks that have been mined for an old parents are rejected by other nodes.

- Blocks need to have a valid nonce and a valid transaction to be accepted.

**4. Your available balance always equals the sum of the UTXOs that can be spent with your private keys**

- Given the nodes have a record of how much money is in each UTXO, it is impossible to spend more than what you own.

- _Also holds in a Byzantine setting._

**5. You cannot spend other people’s coins**

- Coins can only be spent by having knowledge of the private key associated with the UTXO.

- Transactions broadcasted to the network can not be modified by other nodes thanks to digital signatures.

- _Also holds in a Byzantine setting._

## Usage Instructions

### Wallets

On the left side of the screen, 5 different wallets are provided to visualize the wallet interface.

The interface exposes underlying wallet data:

- **Total Balance**: The total balance of the wallet (assumes all sent transactions will be confirmed in the blockchain)
- **Available Balance**: The ready-to-spend balance of this wallet
- **Available UTXOs**: Owned addresses for a wallet. Expanding the the row will display public key that was used to generate the address as well as the private key that can be used to spend the coins
- **Past Transactions**: All past transactions for this wallet

You can also interact with the wallet API by sending a transaction to an address. Try sending a transaction between 2 addresses using the form at the bottom and observe the nodes mining the new block and the transaction being added to the blockchain!

_Note that some data, such as keys and txid has either been truncated or base32 encoded before being displayed to the frontend_

### Blockchain

In the center of the screen the blockchain can be observed. You can expand the blocks to see the transaction's information inside, or scroll all the way down to inspect the genesis block.

Try and check if the information displayed is consistent with the data displayed in the wallets and nodes!

_Note that some data has either been truncated or base32 encoded before being displayed to the frontend_

### Nodes

The POCCoin network is composed of 5 nodes, which are represented on the right side of the screen.

The interface exposes underlying node data:

- **Mining Power**: The percentage of blocks that the node has mined (used to decide validators)
- **Proof of work**: The block on which the node is currently working
- **Mempool**: Transactions in the blockchain Mempool
- **Blockchain UTXOs**: Complete list of UTXOs in the blockchain

Try and send 2 transactions at the same time to observe the mempool getting filled. Note that you might have to send from 2 different wallets if one has a single UTXO available to be spent.
