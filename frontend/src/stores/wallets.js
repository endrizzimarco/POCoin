import { ref, computed } from 'vue'
import { defineStore } from 'pinia'
import axios from 'axios'

const state = {
  total_balance: 0,
  available_balance: 0,
  addresses: [],
  available_utxos: []
}

const endpoints = [
  'http://localhost:3000/balance',
  'http://localhost:3000/available_balance',
  'http://localhost:3000/addresses',
  'http://localhost:3000/available_utxos'
]

const transform_utxos = utxos => {
  const transformed = []
  for (const utxo of utxos) {
    if (transformed.includes(x => x.address === utxo[0])) {
      transformed[transformed.findIndex(x => x.address === utxo[0])].balance += utxo[1].toFixed(2)
    } else {
      transformed.push({
        address: utxo[0],
        balance: utxo[1].toFixed(2)
      })
    }
  }
  return transformed
}

export const useWalletStore = defineStore('walletStore', () => {
  var timers = {}
  const stopPolling = w => {
    clearTimeout(timers[w])
  }

  const wallet = ref({ w1: state, w2: state, w3: state, m: state })
  const addresses = computed(() => {
    return {
      alice: wallet.value.alice?.addresses,
      bob: wallet.value.bob?.addresses,
      charlie: wallet.value.charlie?.addresses
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
      available_utxos: transform_utxos(responses[3].data)
    }
    timers[w] = setTimeout(() => getWalletStats(w), 1000)
  }
  return { wallet, addresses, getWalletStats, stopPolling }
})
