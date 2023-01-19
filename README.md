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

## Development

Refer to the README in the corresponding folder for more information.

- [Frontend](frontend/README.md)
- [Backend](backend/README.md) _(includes instructions for running Paxos tests)_

### Implementation

The repository contains two main components:

1. A backend elixir application implementing a blockchain, as well as client wallet
2. A frontend web application that allows you to interact with the blockchain

Blah blah

#### `wallet.ex`

- The node is not Hierarchal Deterministic (HD) and manages keys separately
- Has it's own mempool of transactions, which waits for change to be available before broadcasting transactions to the network
- Can retry transactions ignored by node (such as when an transaction uses old UTXO)
- Pools node to for new blocks in blockchain

#### `node.ex`

- Manages blockchain
- Verifies transactions
- Runs consensus
- Manages mempool
- Runs PoW

#### `web-server.ex`

Simplet

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
// Exposes various data for a wallet
GET /wallet_stats?w=:wallet
```

```php
// Send money amount from wallet to an address
GET /send?w=:wallet&to_addr=:address&amount=:amount
```

```php
// Generate a new address for a wallet
GET /generate_address?w=:wallet
```

```php
// Exposes various data for a node
GET /node_stats?n=:node
```

```php
// Exposes the whole blockchain
GET /blockchain?n=:node
```

## About POCoin

The POCCoin blockchain is a Bitcoin-inspired proof of concept blockchain. It uses a proof-of-work along Paxos consensus to reach block finality. 

Some simplifications have been made to the blockchain:
  - Every block only contains a single transaction
  - Nodes act as both miners and validators
  - Not fully BFT resistant

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

The node keeps polling 
Whichever node finds the POW first is selected as the next proposer.
Nodes will reject any proposed block whose nonce is not valid. This is untrue sadly !!

Difficulty of POW is fixed and requires nodes to find a hash of the block starting with 6 zeros.

#### Choosing the validators

To select validators, every node keep track of the percentage of blocks
mined by other nodes (mining power).
When a proposer finds a PoW solution, it chooses 3 validators through weighted random selection, where the weight is the mining power of the node.  
This ensures that only nodes that are contributing to the network are selected as validators. Still susceptible to 51% attack.  

To even the playing field, this rule is only applied above height 10 and the proposer is always selected as a validator.

## Service assumptions

### Byzantine Fault Tolerance

The network is not Byzantine resistant. For instance:

- Paxos is used as the consensus algorithm.
- BEB is used as the broadcast algorithm.
- Validators selection has not been implemented. (even though the data is present in the blockchain)

The cryptography used in the blockchain however accounts for Byzantine behavior:

- You cannot double spend or create coins from thin air.
- You can only spend your own coins.
- You cannot modify other people's transactions.
- You can only propose a block if you solve the PoW puzzle.

### Paxos

The nodes assume that a Paxos instance is equal to the block height. This can cause issues when a
an instance is skipped or weh

no adversary

multiple instances is okay

paxos round = block height

### Liveness

How does it handle liveness when multiple people find a block at the same time?

- A transaction sent to a node will always be added to the blockchain, given that at most a minority of blockchain nodes (running Paxos) can crash
- The PoW algorithm will always find a nonce solving the block


### Safety

- You cannot double spend coins
- Your available balance always equals the sum of the UTXOs that can be spent with your private keys
- You cannot spend other people’s coins
- can we have forks ???


## Usage Instructions

### Wallets

On the left side of the screen, 5 different wallets are provided to visualize the wallet interface.

- **Total Balance**: The total balance of the wallet, including pending balance
- **Available Balance**: The ready-to-spend balance of this wallet
- **Available UTXOs**: The UTXOs that are ready to be spent
- **Past Transactions**: The past transactions of the wallet (Transaction ID is truncated to 25 characters)

You can also interact with the wallet by sending a transaction to an address. Try sending a transaction between 2 addresses using the form at the bottom and observe the nodes mining the new block and the transaction being added to the blockchain!

If a node decides to ignore your transaction, the wallet will silently retry it. For example if the UTXOs that were submitted for the transaction have changed since the transaction was sent.

### Blockchain

In the center of the screen the blockchain can be observed. You can expand the blocks to see the transaction's information inside, or scroll all the way down to inspect the genesis block.
(Transaction fields, apart from outputs, are truncated to 25 characters)

### Nodes

The POCCoin network is composed of 5 nodes, which are represented on the right side of the screen. Each tab corresponds to a node and showcases its interface.

- **Mining Power**: The percentage of blocks that the node has mined. (Taken into consideration when selecting the next validators for a block)
- **Proof of work**: The block on which the node is currently working.
- **Mempool**: Transactions in the blockchain Mempool.
- **Blockchain UTXOs**: All the UTXOs on the node's blockchain. (Must be consistent across nodes)
