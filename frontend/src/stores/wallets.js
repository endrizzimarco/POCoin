import { ref, computed } from 'vue'
import { defineStore } from 'pinia'
import axios from 'axios'

const state = {
  total_balance: 0,
  available_balance: 0,
  addresses: [],
  available_utxos: [],
  history: []
}

// lol
const endpoints = [
  `http://${location.hostname}:3000/balance`,
  `http://${location.hostname}:3000/available_balance`,
  `http://${location.hostname}:3000/addresses`,
  `http://${location.hostname}:3000/available_utxos`,
  `http://${location.hostname}:3000/history`,
  `http://${location.hostname}:3000/pending`
]

export const useWalletStore = defineStore('walletStore', () => {
  var intervals = {}
  const stopPolling = w => {
    clearInterval(intervals[w])
  }

  const wallet = ref({ w1: state, w2: state, w3: state, w4: state, w5: state })

  const addresses = computed(() => {
    const wallets = [
      { name: 'Alice', w: 'w1' },
      { name: 'Bob', w: 'w2' },
      { name: 'Charlie', w: 'w3' },
      { name: 'Marco', w: 'w4' },
      { name: 'Georgi', w: 'w5' }
    ]
    return wallets.map(obj => {
      return {
        label: obj.name,
        options: wallet.value[obj.w].addresses.map(obj => {
          return { value: Object.keys(obj)[0], label: Object.keys(obj)[0] }
        })
      }
    })
  })

  const getWalletStats = async w => {
    const responses = await axios.all(
      endpoints.map(endpoint =>
        axios.get(endpoint, {
          params: {
            wallet: w
          }
        })
      )
    )
    wallet.value[w] = {
      total_balance: responses[0].data,
      available_balance: responses[1].data,
      addresses: responses[2].data,
      available_utxos: responses[3].data.map(utxo => {
        return { address: utxo[0], balance: utxo[1].toFixed(2) }
      }),
      history: responses[4].data.map(x => {
        return {
          block: x[0],
          type: x[1],
          txid: x[2].substring(0, 25),
          amount: x[3].toFixed(2)
        }
      }),
      next_pending: responses[5].data
    }
  }

  const pollWallet = w => {
    getWalletStats(w)
    intervals[w] = setInterval(() => getWalletStats(w), 500)
  }

  const initWalletsState = () => {
    ;['w1', 'w2', 'w3', 'w4', 'w5'].forEach(w => {
      getWalletStats(w)
    })
  }
  return { wallet, addresses, initWalletsState, pollWallet, stopPolling }
})
