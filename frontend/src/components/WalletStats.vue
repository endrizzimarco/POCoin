<script setup>
import WalletSendForm from '@/components/WalletSendForm.vue'
import { defineProps, onMounted, computed } from 'vue'
import { useWalletStore } from '@/stores/wallets'
import { message } from 'ant-design-vue'
import axios from 'axios'

const props = defineProps({
  wallet: String
})

const store = useWalletStore()
const state = computed(() => store.wallet[props.wallet])

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

const generateAddress = async () => {
  const response = await axios.get('http://localhost:3000/generate_address', {
    params: {
      wallet: props.wallet
    }
  })
  response.status === 200
    ? message.success('Successfully generated address')
    : message.error('Failed to generate address')

  console.log('addresses', store.addresses[0])
}

onMounted(() => {
  store.getWalletStats(props.wallet)
})
</script>

<template lang="pug">
a-row
  a-col(:span='12')
    a-statistic(title='Total Balance', :precision=2, :value='state.total_balance')
  a-col(:span='12')
    a-statistic(title='Available Balance', :precision=2, :value='state.available_balance')
.mt-5
  p.pb-3.opacity-50(style='font-weight: 420') Available UTXOs
  a-table(:columns='tableCols', :data-source='state.available_utxos', size='small', :pagination='false')
    template(#bodycell='{ column, text }')
      template(v-if='column.dataIndex === "name"')
        a {{ text }}
    template(#expandedRowRender)
      p Public and private keys go here
p.pt-6.opacity-50(style='font-weight: 420') Generate Address
a-button.mt-2(@click='generateAddress') Generate Address
p.pt-6.opacity-50(style='font-weight: 420') Send coins
WalletSendForm.mt-2(:available_balance='state.available_balance')
</template>
