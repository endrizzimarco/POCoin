import { defineStore } from 'pinia'
import { ref } from 'vue'
import axios from 'axios'

const state = {
  current: 0,
  mempool: [],
  utxos: []
}

// lol
const endpoints = [
  'http://localhost:3000/mempool',
  'http://localhost:3000/node_utxos',
  'http://localhost:3000/working_on'
]

export const useNodeStore = defineStore('nodesStore', () => {
  var intervals = {}
  const stopPolling = w => {
    clearInterval(intervals[w])
  }

  const node = ref({ n1: state, n2: state, n3: state, n4: state, n5: state })

  const getNodeStats = async n => {
    const responses = await axios.all(
      endpoints.map(endpoint =>
        axios.get(endpoint, {
          params: {
            node: n
          }
        })
      )
    )
    node.value[n] = {
      mempool: responses[0].data.map(txid => {
        return { txid: txid.substring(0, 25) }
      }),
      utxos: responses[1].data.map(utxo => {
        return { address: utxo[0], balance: utxo[1].toFixed(2) }
      }),
      current: responses[2].data
    }
  }

  const pollNode = n => {
    getNodeStats(n)
    intervals[n] = setInterval(() => getNodeStats(n), 200)
  }

  const initNodesState = () => {
    ;['n1', 'n2', 'n3', 'n4', 'n5'].forEach(n => {
      getNodeStats(n)
    })
  }
  return { node, initNodesState, pollNode, stopPolling }
})
