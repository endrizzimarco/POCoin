<script setup>
import WalletSendForm from '@/components/WalletSendForm.vue'
import { defineProps, reactive, onMounted, onUnmounted } from 'vue'
import axios from 'axios'
import { message } from 'ant-design-vue'

var timer = null
var loading = true

const props = defineProps({
  wallet: String
})

const state = reactive({
  scanned_blockchain_height: 0,
  total_balance: 0,
  available_balance: 0,
  addresses: [],
  available_utxos: []
})
const tableCols = [
  {
    title: 'Address',
    dataIndex: 'address',
    key: 'address'
  },
  {
    title: 'Balance',
    dataIndex: 'balance',
    key: 'balance',
    width: 10,
    align: 'right'
  }
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

const getWalletStats = async () => {
  const endpoints = [
    'http://localhost:3000/balance',
    'http://localhost:3000/available_balance',
    'http://localhost:3000/addresses',
    'http://localhost:3000/available_utxos'
  ]

  const responses = await axios.all(
    endpoints.map(endpoint =>
      axios.get(endpoint, {
        params: {
          wallet: props.wallet
        }
      })
    )
  )
  state.total_balance = responses[0].data
  state.available_balance = responses[1].data
  state.addresses = responses[2].data
  state.available_utxos = transform_utxos(responses[3].data)
  loading = false
  timer = setTimeout(getWalletStats, 1000)
}

const generateAddress = async () => {
  const response = await axios.get('http://localhost:3000/generate_address', {
    params: {
      wallet: props.wallet
    }
  })
  response.status === 200
    ? message.success('Successfully generated address')
    : message.error('Failed to generate address')
}

onMounted(async () => {
  console.log('mounted' + props.wallet)
  await getWalletStats()
})

onUnmounted(() => {
  console.log('unmounted' + props.wallet)
  clearTimeout(timer)
})
</script>

<template lang="pug">
a-skeleton(active, v-if='loading')
a-row
  a-col(:span='12')
    a-statistic(title='Total Balance', :precision=2, :value='state.total_balance')
  a-col(:span='12')
    a-statistic(title='Available Balance', :precision=2, :value='state.available_balance')
.mt-5
  p.pb-3(style='color: #8fb7df') Available UTXOs
  a-table(:columns='tableCols', :data-source='state.available_utxos', bordered, size='small', :pagination='false')
    template(#bodycell='{ column, text }')
      template(v-if='column.dataIndex === "name"')
        a {{ text }}
WalletSendForm.mt-5(:available_balance='state.available_balance')
a-button.mt-5(@click='generateAddress') Generate Address
</template>
