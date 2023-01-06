<script setup>
import { ref } from 'vue'

const visible = ref(false)
</script>

<template lang="pug">
.flex.w-full
  .flex.cursor-pointer
    img(alt='logo', src='@/assets/logo.svg', width='35', height='35')
    p.ml-3.mt-2.text-2xl.text-white POCoin
  p.header-subtitle(style='margin-top: 0.54rem') |
  p.header-subtitle(style='margin-top: 0.64rem') A Blockchain visualization
  a-button.ml-auto.mr-2.text-white.top-2(@click='visible = true', style='background-color: transparent') About
  a-modal(
    :visible='visible',
    :title='`About this project`',
    @ok='visible = false',
    @cancel='visible = false',
    style='top: 10vh; width: 40vw'
  )
    p.pb-5 POCoin is a blockchain visualization tool that allows you to inspect how a cryptocurrency works.

    p.pb-5
      span.font-semibold Usage Instructions: Wallets
      span &nbsp; On the left side of the screen, 5 different wallets are provided to visualize various endpoints of the wallet API. 
      span You can also interact with the wallet API by either generating a new address or sending a transaction to an address. 
      span Try sending a transaction between 2 addresses and observe the nodes mining the new block and the transaction being added to the blockchain!

    p.pb-5
      span.font-semibold Usage Instructions: Blockchain
      span &nbsp; On the center of the screen the blockchain can be observed. You can expand the blocks to see the transactions inside, or scroll 
      span all the way up to inspect the genesis block.

    p.pb-5
      span.font-semibold Usage Instructions: Nodes
      span &nbsp; The POCCoin network is composed of 5 nodes, which are represented by each tab on the right side of the screen. The 
      span node API has been used to expose whether a node is working on a block, its transaction queue, aswell as the complete  UTXOs set for the blockchain.

    p.pb-5
      span.font-semibold About POCCoin
      span &nbsp; The POCCoin blockchain is a simplified version of the Bitcoin blockchain. 
      span The network does not use Byztantine resistant algorithms, but the cryptography that makes a cryptocurrency secure has been fully implemented. 
      span Other simplifications are that every block contains a single transaction only and nodes run the POW themselves as opposed to using a distributed network of miners.

    p 
      span.font-semibold Initial Setup
      span &nbsp; Since there are no miners to mine new currency, the genesis block assigns 1000 coins to Alice, which distributes 200 each to 
      span her friends Bob, Charlie, Marco and Georgi.
</template>

<style scoped>
.header-subtitle {
  @apply font-thin text-xl text-white ml-3;
}
</style>
