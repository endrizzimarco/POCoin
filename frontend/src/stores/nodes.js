import { defineStore } from 'pinia'
import { ref } from 'vue'
import axios from 'axios'

const state = {
  current: 0,
  mempool: [],
  utxos: []
}

export const useNodeStore = defineStore('nodesStore', () => {
  var intervals = {}
  const stopPolling = w => {
    clearInterval(intervals[w])
  }

  const node = ref({ n1: state, n2: state, n3: state, n4: state, n5: state })

  const getNodeStats = async n => {
    const responses = await axios.get(`http://${location.hostname}:3000/node_stats?node=${n}`)
    node.value[n] = responses.data
  }

  const pollNode = n => {
    getNodeStats(n)
    intervals[n] = setInterval(() => getNodeStats(n), 1000)
  }

  const initNodesState = () => {
    ;['n1', 'n2', 'n3', 'n4', 'n5'].forEach(n => {
      getNodeStats(n)
    })
  }
  return { node, initNodesState, pollNode, stopPolling }
})
