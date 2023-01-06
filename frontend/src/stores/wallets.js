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
  'http://localhost:3000/balance',
  'http://localhost:3000/available_balance',
  'http://localhost:3000/addresses',
  'http://localhost:3000/available_utxos',
  'http://localhost:3000/history'
]

export const useWalletStore = defineStore('walletStore', () => {
  var intervals = {}
  const stopPolling = w => {
    clearInterval(intervals[w])
  }

  const wallet = ref({ w1: state, w2: state, w3: state, m: state })
  const addresses = computed(() => {
    return {
      alice: wallet.value['w1']?.addresses.map(obj => Object.keys(obj)[0]),
      bob: wallet.value['w2']?.addresses.map(obj => Object.keys(obj)[0]),
      charlie: wallet.value['w3']?.addresses.map(obj => Object.keys(obj)[0]),
      master: wallet.value['m']?.addresses.map(obj => Object.keys(obj)[0])
    }
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
      })
    }
  }

  const pollWallet = w => {
    intervals[w] = setInterval(() => getWalletStats(w), 1000)
  }

  const initWalletsState = () => {
    ;['w1', 'w2', 'w3', 'm'].forEach(w => {
      getWalletStats(w)
    })
  }
  return { wallet, addresses, initWalletsState, pollWallet, stopPolling }
})
