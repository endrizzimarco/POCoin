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
    const r = await axios.get(`http://${location.hostname}:3000/wallet_stats?wallet=${w}`)
    wallet.value[w] = r.data
  }

  const pollWallet = w => {
    getWalletStats(w)
    intervals[w] = setInterval(() => getWalletStats(w), 1000)
  }

  const initWalletsState = () => {
    ;['w1', 'w2', 'w3', 'w4', 'w5'].forEach(w => {
      getWalletStats(w)
    })
  }
  return { wallet, addresses, initWalletsState, pollWallet, stopPolling }
})
